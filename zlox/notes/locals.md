
# Locals in ZLox

The book uses a clever optimization when dealing with local variables in scope blocks.
Because of the constraints we put on variable definitions with scopes, and the fact
that statements (minus var declarations) don't leave anything on the stack when done,
we can safely store locals **directly on the stack** and can guarantee that the
instructions that use the local are able to find its value in memory.

### How this looks: the VM

Typically our lox code discards values once used in a statement:

```lox
// Global scope
var x = 3;

print x + 2;
```

```
                +-----+
GET_GLOBAL "x"  |  3  |
                +-----+
                +-----+-----+
CONST 2         |  3  |  2  |
                +-----+-----+
                +-----+
ADD             |  5  |
                +-----+
                +
PRINT           |
                +
```

Even without print, our compiler explicitly adds a `POP` command to discard the value
of the bare expression.

The stack is used as the workspace for computing the expression, but the final answer
is discarded after use.

With locals, something interesting happens.

```lox
// global scope
var x = 3;
{
    var y = x + 1;

    print y * 2;
}
```
Our expression is computed, but there is no "side effect" command like print.
```
                +-----+
GET_GLOBAL "x"  |  3  |
                +-----+
                +-----+-----+
CONST 2         |  3  |  2  |
                +-----+-----+
                +-----+
ADD             |  5  |
                +-----+
```
After this line, the stack has one more element on it that contains the initial value
of the local. This leftover slot in the stack IS the local! The `print` statement
compiles to this:

```
                +-----+-----+
GET_LOCAL[0]    |  5  |  5  |
                +-----+-----+
                +-----+-----+-----+
CONST 2         |  5  |  5  |  2  |
                +-----+-----+-----+
                +-----+------+
MULT            |  5  |  10  |
                +-----+------+
                +-----+
PRINT           |  5  |
                +-----+
```
The `GET_LOCAL[0]` gets the value in the stack slot corresponding to the relevant local.
To be clear, the instruction isn't looking the local up by name, but by
**position in the stack**.

This copy becomes the operand in the rest of the expression. We load a 2 and multiply,
then after printing, we discard that working value, still left with the original slot
for the local in our stack.

Once we leave our scope, the VM issues POP commands to remove all of the locals that
are now out of scope.

To reiterate, while the name "y" is in the code, the compiled bytecode doesn't track
the original name of the local. Instead, the compiler computes where the local will be
in the frame; then all bytecode needs to do is reference that stack position.

### How this looks: The Compiler
You may be curious how the compiler knows and can guarantee that a local will be
in a certain place at a certain time to "pre-bake" lookup positions in the bytecode.
The following rules make this possible:

1. All non-declaration statements discard their operand from the stack.
2. All lines of lox are executed in top-down order
3. All nested scopes will always be in the same shape.
4. Locals for a particular scope are immediately invalid after the scope ends.

#### 1. All non-declaration statements discard their operand.
Generally, if statements left stack elements willy-nilly, this would be a problem.
along with wasted memory, we wouldn't be able to ensure that a local is where it
needs to be. Imagine the following:

```lox
// non-global
var x = 3;
if (random() > 0.5) {
    x + 2;
}
var y = 6;
```

Half of the time, the stack would include a random `5` that hangs out. We can't
determine whether Y will be in position 1 or position in the stack if this were true.
Removing locals would be really hard in this case as well, as we wouldn't be able to
guarantee that the top of the stack is a local or an orphan value.

#### All lines of lox are executed in top-down order
When getting/setting locals, we refer to them by an index/positional number. This
number corresponds to the order that these locals were declared.

If lox had naive out-of-order execution, there would be no guarantee whether

```lox
// non-global
var x = 3;
var y = 4;
```

would lead to a stack of `[3, 4]` or a stack of `[4, 3]`.

#### When a scope ends, its locals are no longer valid
The following code is invalid:
```lox
if (true) {
    var y = 3;
}
print y - 2;
```
Though the block is always guaranteed to run, there is a hard rule in lox that local
variables are discarded immediately when the scope exits.

Of course, this constraint is part of our guarantee that the stack will have a 
particular shape at this point in the code. Consider:
```lox
var x = 100;
if (flag) {
    var y = 20;
}
print x + 3;
```
if `flag` is false, the block will not run and so y will never be defined. If `flag` is
true, the block will run and add a stack value for the local `y`. However, once we 
leave the if-block's scope, `y` is popped off of the stack. In both scenarios, once
we get to `print x + 3;`, the stack contains only the slot for the local `x`. To
that print statement, the code above looks like:

```lox
var x = 100;
// if... if who?
print x + 3;
```

#### Nested scopes will always have the same shape.

consider:
```lox
{
  var y = 3;
  {
    var x = 2;
    {
      var z = y + x;
      ...
    }
  }
}
```

The innermost block will always have the `var x = 2;` block as a parent, as will that
block have `var y = 3` as a parent. So when we reach `var z = y + x;`, we know that:
* the `y` local was defined first in the outermost scope
* The `x` local was defined second in the middle scope

So the compiler is able to conceptually treat this line as 
`var z = {the first local} + {the second local}`


### How the compiler tracks locals.

The compiler maintains its own `local stack` in memory while compiling code.
This stack represents the "currently active locals" at the point that the compiler is
at in the source code. The contents of the stack are local names and their metadata:

```
+---------------------+
| ("Z", scopeDepth=1) |
+---------------------+
| ("y", scopeDepth=1) |
+---------------------+
| ("x", scopeDepth=2) |
+---------------------+
```
the string is the local's name in the source code, and the scopeDepth is the number
of nested scopes deep that this local is defined.

The stack data structure is used because the locals behave like a stack:

```
{
    // Push y
    var y = 44;
    {
        // Push x
        var x = ...;

        // do stuff with x
    } 
    // Left scope. pop x.
}
// Left scope. Pop y.
```

this stack is **compiler-wide**, not scope-wide. All locals for a particular compiled
chunk go together in one stack so that locals defined in a parent scope can be accessed
by the child scope.

The management of this stack is easy, as we just need to push a new local slot when we 
encounter its declaration, and pop that local once its scope exits.

This way, when we encounter the local's name in a statement, it's simply a matter
of where in the local stack that local is; the position of the local in the compiler
stack will correspond to its position in the vm's value stack. Again, this is because
**the order that the locals are parsed is the same order in which they are defined**.

## Function calls
We treat the arguments of functions as locals of that function body. This decision
affects the **calling convention** for our lox functions.

When the parser encounters a function definition, it does a few things:
First, it creates a new "sub-compiler" which will handle compilation of the function 
body. This is a completely separate compiler with its own data chunk and local stack.
For each argument in the function, a local entry is pushed onto the subcompiler's local
stack, indicating that the first {arity} locals of the function will be its arguments.
Much like a bare scope, after the function returns, all argument locals and locals 
defined in the function body are popped.

The calling convention for the function, then:
* load the function definition onto the stack
* evaluate each argument expression in the call, but don't pop it
  - also, evaluate from left to right to match the parser order!


