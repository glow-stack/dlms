module lms;

interface Box {}

// Stage is equivalent to DI container (or rather DI is simple late-binding + basic form of staging)
// but the composition and execution of them is independent
// and encapsulated by Lift!T interface
interface Stage {
    /// Lift a simple constant
    Lift!T lift(T)(T value) {
        return new Constant!T(value);
    }

    /// Lift a placeholder - slot for concrete value to be filled in at a later stage
    Lift!T slot(T)() {
        return new Slot!T();
    }

    /// Try to evaluate (lower) lifted value using this stage
    auto eval(T)(Lift!T value) {
        return value.eval(this);
    }

    /// Do partial evaluation for lifted value, this folds all known-constant sub-tries and optimizes expressions
    auto partial(T)(Lift!T value) {
        return value.partial(this);
    }
}

// run-time Stage container
class Runtime : Stage { }

// compile-time Stage container
class CompileTime : Stage { }

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
}

// Simpliest of all - just a constant, stays the same, regardless of stage
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

// Lifted map function call
class Mapped(T, U) : Lift!U {
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

class FlatMapped(T, U) : Lift!U {
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

// Lifted unary operation
class Unary(T, string op) : Lift!T {
    this(Lifted!T operand) {
        this.value = operand;
    }

    T eval(Stage stage) {
        return mixin(op ~ "value.eval(stage)");
    }

    Lift!T partial(Stage stage) {
        return value.partial(stage).map((x){
            return mixin(op ~ "x");
        });
    }

    private Lift!T value;
}

// Lifted binary operaton
class Binary(T, string op) : Lift!T {
    this(Lifted!T lhs, Lifted!T rhs) {
        this.lhs = lhs;
        this.rhs = rhs;
    }

    T eval(Stage stage) {
        return mixin("lhs.get(stage) "~op~"rhs.get(stage)");
    }

    Lift!T partial(Stage stage) {
        auto newLhs = lhs.partial();
        auto newRhs = rhs.partial();
        //TODO: compute value if both sides are const
        return new Binary(newLhs, newRhs);
    }

    private Lifted!T lhs, rhs;
}

unittest {
    auto stage = new CompileTime();
    auto value = stage.lift(40);// + 2;
    assert(stage.eval(value) == 40);
}
