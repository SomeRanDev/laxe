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

Function arguments can be provided using parentheses after the function name. The typing syntax is the same as Haxe's. Laxe is a statically typed language, but Haxe can infer some types, so while they aren't necessary, types are recommended:
```python
def myFunctionName(myParam1, myParam2: str):
    trace(myParam1)
    trace(myParam2) # myParam2 is a String


def addTwoNumbers(one: int, two: int):
    trace(one + two)
```

[NEXT >>]()