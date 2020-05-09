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
        register(name, lifted);
        return lifted;
    }

    /// Register existing slot at this _stage_ with name `name`
    Slot!T slot(T)(string name, Slot!T value) {
        register(name, value);
        value.reset();
        return value;
    }

    /// Register existing slot at this _stage_ with original name
    Slot!T slot(T)(Slot!T value) {
        register(value.name, value);
        value.reset();
        return value;
    }

    /// Try to evaluate (lower) lifted value using this stage
    auto eval(T)(Lift!T value) {
        return value.eval(this);
    }

    /// Do partial evaluation for lifted value, this folds all known-constant sub-tries and optimizes expressions
    auto partial(U)(U value) 
    if (!is(U : Slot!T, T)) {
        return value.partial(this);
    }

    ///ditto
    auto partial(U)(U value)
    if (is(U : Slot!T, T)) {
        return cast(Lift!T)this[value];
    }

    void register(T)(Slot!T slot) {
        register(slot.name, typeid(T));
    }

    /// This is an implementation hook - register must save name,typeinfo pair to check type matching later
    void register(string name, Box box);

    /// This is an implementation hook - bind must check that typeinfo matches and bind value to the lifted slot
    Box opIndexAssign(Box value, string name);

    /// Third implementation hook - lookup bound value for a given name
    Box opIndex(string name);
}

/**
    Simple stage that keeps slots as key-value pairs in built-in AA.

    Could be used as is or as an example to build your own stage(s).
*/
class BasicStage : Stage { 
    override void register(string name, Box box) {
        if (name in slots) throw new LmsNameConflict("This stage already has slot for '"~name~"' variable");
        slots[name] = box;
    }

    override Box opIndexAssign(Box lifted, string name) {
        auto p = name in slots;
        if (!p) throw new LmsNameResolution("This stage doesn't have '"~name~"' variable");
        slots[name].replace(lifted);
        return lifted;
    }

    override Box opIndex(string name) {
        auto p = name in slots;
        if (!p) throw new LmsNameResolution("This stage doesn't have '"~name~"' variable");
        return slots[name];
    }

    private Box[string] slots;
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
        expr = lift(T.init).map(delegate T (T x){
            throw new LmsEvaluationFailed("slot "~_name~" has no bound value at this stage");
        });
    }

    override T eval(Stage stage) {
        return expr.eval(stage);
    }

    override Lift!T partial(Stage stage) {
        return expr;
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
        import std.stdio : writeln;
        auto v = liftedArg.partial(stage);
        auto c = cast(Constant!T)v;
        if (c) return lift(func(c.eval(stage)));
        return v.map(func);
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

///
@("basics")
unittest {
    auto stage = new BasicStage();
    auto value = lift(40) + 2;
    assert(stage.eval(value) == 42);
}

///
@("slots")
unittest {
    auto stage = new BasicStage();
    auto slot = stage.slot!string("some.slot");
    assert(slot.name == "some.slot");
    auto expr = slot ~ ", world!";
    assertThrows(stage.eval(expr));
    
    stage["some.slot"] =  lift("Hello");
    assert(stage.eval(expr) == "Hello, world!");

    auto laterStage = new BasicStage();
    laterStage.slot(slot);
    assertThrows(laterStage.eval(slot));

    laterStage["some.slot"] = lift("Bye");

    assert(stage.eval(expr) == "Bye, world!");
}


///
@("partial evaluation")
unittest {
    auto stage = new BasicStage();
    int[] trace; // our primitive trace buffer
    auto v1 = stage.slot!double("var1").map(delegate double(double x) {
        trace ~= 1;
        return x;
    });
    auto v2 = stage.slot!double("var2").map(delegate double(double x) {
        trace ~= 2;
        return x;
    });
    stage["var1"] = lift(1.5);
    auto part = (v1 + v2).partial(stage);
    stage["var2"] = lift(-0.5);
    // first pass - both map functions called once
    assert(part.eval(stage) == 1.0);
    assert(trace == [1, 2]);

    // second pass - only v2 is evaluated
    assert(part.eval(stage) == 1.0);
    assert(trace == [1, 2, 2]);
}