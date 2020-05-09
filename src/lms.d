module lms;

class Box {
    // replace value of this box with another, may throw if cannot do that
    void replace(Box another) {
        throw new LmsException("Internal error - cannot replace contents of this lifted value");
    }
}

/// Lift a simple constant
Lift!T lift(T)(T value) 
if (!is(T : Lift!U, U)){
    return new Constant!T(value);
}

/// ditto
Lift!T lift(T)(Lift!T lifted) {
    return lifted;
}

/**
    Stage is equivalent to DI container (or rather DI is simple late-binding + basic form of staging)
    but the composition and execution of them is independent
    and encapsulated by Lift!T interface
    
    A user is expected to sub-class and define custom stages as needed. See also `BasicStage`.
*/
interface Stage {    
    /// Lift a placeholder - slot for concrete value to be filled in at a later stage
    Slot!T slot(T)(string name) {
        auto lifted = new Slot!T(name);
        register(name, typeid(T), lifted);
        return lifted;
    }

    /// Register existing slot at this _stage_ with name `name`
    Slot!T slot(T)(string name, Slot!T value) {
        register(name, typeid(T), value);
        value.reset();
        return value;
    }

    /// Register existing slot at this _stage_ with original name
    Slot!T slot(T)(Slot!T value) {
        register(value.name, typeid(T), value);
        value.reset();
        return value;
    }

    /// Try to evaluate (lower) lifted value using this stage
    auto eval(T)(Lift!T value) {
        return value.eval(this);
    }

    /// Do partial evaluation for lifted value, this folds all known-constant sub-tries and optimizes expressions
    auto partial(T)(Lift!T value) {
        return value.partial(this);
    }

    void register(T)(Slot!T slot) {
        register(slot.name, typeid(T));
    }

    /// This is an implementation hook - bind must check that typeinfo matches and bind value to the lifted slot
    void bind(string name, Box value);

    /// This is an implementation hook - register must save name,typeinfo pair to check type matching later
    void register(string name, TypeInfo info, Box box);
}

/**
    Simple stage that keeps slots as key-value pairs in built-in AA.

    Could be used as is or as an example to build your own stage(s).
*/
class BasicStage : Stage { 
    override void register(string name, TypeInfo info, Box box) {
        if (name in slots) throw new LmsNameConflict("This stage already has slot for '"~name~"' variable");
        slots[name] = info;
        slotValues[name] = box;
    }

    override void bind(string name, Box lifted) {
        if (name !in slotValues) throw new LmsNameResolution("This stage doesn't have '"~name~"' variable");
        slotValues[name].replace(lifted);
    }

    private TypeInfo[string] slots;
    private Box[string] slotValues;
}

// Lifted value of type T
abstract class Lift(T) : Box {
    // full evaluation, may fail if some variables are not defined at this stage
    abstract T eval(Stage stage);   
    // partial evaluation given all of variables we know at this stage
    abstract Lift!T partial(Stage stage);
    //
    final Lift!U map(U)(U delegate(T) mapFunc) {
        return new Mapped!(T, U)(this, mapFunc);
    }
    //
    final Lift!U flatMap(U)(Lift!U delegate(T) mapFunc) {
        return new FlatMapped!(T, U)(this, mapFunc);
    }

    ///
    auto opBinary(string op, U)(U rhsV)
    if (!is(U : Lift!V, V)) {
        return map((lhsV){
            return mixin("lhsV "~op~" rhsV");
        });
    }

    ///
    auto opBinary(string op, U)(U rhs) 
    if (is(U : Lift!V, V)) {
        return flatMap((lhsV) {
            return rhs.map((rhsV) {
                return mixin("lhsV "~op~" rhsV");
            });
        });
    }
}

/// Simpliest of all - just a constant, stays the same, regardless of _stage_
class Constant(T) : Lift!T {
    this(T value) {
        this.value = value;
    }

    override T eval(Stage stage) { 
        return value; 
    }

    override Lift!T partial(Stage stage) {
        return this;
    }
    
    private T value;
}

/// Slot - a placeholder for value, that will be provided at a later _stage_
class Slot(T) : Lift!T {
    this(string name) {
        _name = name;
        reset();
    }

    override void replace(Box another) {
        expr = cast(Lift!T)another;
    }

    void reset() {
        expr = lift(T.init).map(delegate T (string x){
            throw new LmsEvaluationFailed("slot "~_name~" has no bound value at this stage");
        });
    }

    override T eval(Stage stage) {
        return expr.eval(stage);
    }

    override Lift!T partial(Stage stage) {
        return expr.partial(stage);
    }

    string name() { return _name; }

    private string _name;
    private Lift!T expr;
}

// Lifted map function call
private class Mapped(T, U) : Lift!U {
    this(Lift!T arg, U delegate(T) func) {
        this.liftedArg = arg;
        this.func = func;
    }

    override U eval(Stage stage) { 
        return func(liftedArg.eval(stage)); 
    }

    override Lift!U partial(Stage stage) {
        return liftedArg.partial(stage).map((arg){
            return func(arg);
        });
    }

    private Lift!T liftedArg;
    private U delegate(T) func;
}

private class FlatMapped(T, U) : Lift!U {
    this(Lift!T arg, Lift!U delegate(T) func) {
        this.liftedArg = arg;
        this.func = func;
    }

    override U eval(Stage stage) { 
        return func(liftedArg.eval(stage)).eval(stage); 
    }

    override Lift!U partial(Stage stage) {
        return liftedArg.partial(stage).flatMap((arg){
            return func(arg);
        });
    }

    private Lift!T liftedArg;
    private Lift!U delegate(T) func;
}

class LmsException : Exception {
    this(string message) {
        super(message);
    }
}

class LmsNameResolution : LmsException {
    this(string message) {
        super(message);
    }
}

class LmsNameConflict : LmsNameResolution {
    this(string message){
        super(message);
    }
}

class LmsEvaluationFailed : LmsException {
    this(string message){
        super(message);
    }
}

version(unittest) {
    void assertThrows(T)(lazy T expr) {
        try {
            expr;
        }
        catch(LmsException e) {
            return;
        }
        assert(0, expr.stringof ~ " should throw but didn't!");
    }
}

@("basics")
unittest {
    auto stage = new BasicStage();
    auto value = lift(40) + 2;
    assert(stage.eval(value) == 42);
}

@("slots")
unittest {
    auto stage = new BasicStage();
    auto slot = stage.slot!string("some.slot");
    assert(slot.name == "some.slot");
    auto expr = slot ~ ", world!";
    assertThrows(stage.eval(expr));
    
    stage.bind("some.slot", lift("Hello"));
    assert(stage.eval(expr) == "Hello, world!");

    auto laterStage = new BasicStage();
    laterStage.slot(slot);
    assertThrows(laterStage.eval(slot));

    laterStage.bind("some.slot", lift("Bye"));

    assert(stage.eval(expr) == "Bye, world!");
}
