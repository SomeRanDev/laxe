# Variables
Unlike Python, Laxe uses a Haxe-like syntax for declaring new variables. `var` is used for new mutable variables, while `const` is used for immutable variables.
```python
def main:
    var a = 164 # declared
    a = 0       # reassigned

    b = 12      # error: b is not defined

    const c = "test"
    c = "fail"  # error: c is final variable
```

[NEXT >>]()