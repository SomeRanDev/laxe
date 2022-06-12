# Functions
Functions are based on Python.

Using `def` functions can be created using the following syntax:
```python
def myFunctionName:
    # insert function code here
```

Similar to Python, Laxe uses whitespace to denote when the function body begins/ends. All of the function content must retain the same identation:
```python
def myFunctionName:
    var a = 12
    trace(a)
      a += 1 # inconsistent identation
```

&nbsp;

## Arguments

Function arguments can be provided using parentheses after the function name. The typing syntax is the same as Haxe's. Laxe is a statically typed language, but Haxe can infer some types, so while they aren't necessary, types are recommended:
```python
def myFunctionName(myParam1, myParam2: str):
    trace(myParam1)
    trace(myParam2) # myParam2 is a String


def addTwoNumbers(one: int, two: int):
    trace(one + two)
```

&nbsp;

## Return Type

Function return types can be specified using `->`. Similar to argument types, the Haxe compiler will attempt to infer them otherwise.
```python
def getSum(one: int, two: int) -> int:
    return one + two
```

&nbsp;

## Shorthand Definitions

Similar to Python, if only one expression is required for the function body, it can be placed beside the `:`:
```python
def getSum(one: int, two: int) -> int: return one + two
```

Function declarations that only contain a return statement can be shortened further using the `=` operator. Instead of the `:`, use `=` followed by the desired expression to be returned.
```python
def getSum(one: int, two: int) -> int = one + two
```

&nbsp;

## Functions in Expressions

Functions can be declared as expressions:
```python
def main
    def exprFunc:
        trace("called local function")

    exprFunc()
```

Functions can also be assigned to variables. In cases like this, they can be left unnamed as well.
```python
def main:
    const exprFunc = def:
        trace("called localfunction")

    exprFunc()
```

[NEXT >>]()
