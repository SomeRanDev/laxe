# LAXE
A Python-like programming language built entirely using Haxe metaprogramming. It is converted to Haxe AST and 100% interoperable with Haxe projects/libraries.

## Hypothetically, this is how it would work:

---

Install from haxelib
```hxml
haxelib install laxe
```

---

Add to project, and set class path to `src/`.

Class path can be the same as `-cp`.

You can even mix `.hx` and `.lx` within the same directory.
```hxml
-lib laxe

-D laxe-cp=src
```

---

Make some `.lx` files and put some Laxe code inside.

```python
def main():
  trace("Hello there.")
```
