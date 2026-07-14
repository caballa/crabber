# CrabIR — VSCode syntax highlighting

A VSCode extension providing syntax highlighting, comment toggling, bracket
matching and indentation for CrabIR (`*.crabir`) files. It is the VSCode
counterpart to `emacs-mode/crabir-mode.el`.

## What it highlights

- Comments (`# ...`)
- `cfg` and block labels (`start:`, `loop:`, ...)
- String literals (`cfg("foo")`)
- Types (`i1`, `i8`, `i16`, `i32`, `i64`, `i256`, ... any `iN`)
- Integer literals
- Constants / declarations (`declare`, `true`, `false`)
- Arithmetic & logical operators (`add`, `sub`, `mul`, `sdiv`, `udiv`, `urem`,
  `srem`, `and`, `or`, `xor`, `not`)
- Control instructions (`if`, `else`, `goto`, `assume`, `unreachable`)
- Verification instructions (`havoc`, `assert`) and `EXPECT_*` test macros
- Special instructions (`call`, `ite`)
- Casts (`trunc`, `sext`, `zext`)
- Array/memory/region operations (`array_store`, `array_load`, `array_assign`,
  `region_init`, `region_copy`, `region_cast`, `make_ref`, `remove_ref`,
  `load_from_ref`, `store_to_ref`, `gep_ref`, `ref_to_int`, `int_to_ref`)
- Intrinsics (`value_partition_start`, `value_partition_end`)
- Global variables (`@name`)

## Install (local / development)

Copy or symlink this folder into your VSCode extensions directory:

```sh
# macOS / Linux
ln -s "$(pwd)/vscode-mode" ~/.vscode/extensions/crabir-0.1.0
```

Then reload VSCode (`Developer: Reload Window`, or just restart it). Any
`*.crabir` file will now be highlighted. You can confirm the language is active
in the bottom-right of the status bar — it should read **CrabIR**.

To try it without installing, open this folder in VSCode and press `F5` to
launch an Extension Development Host, then open a file from `../samples/`.

## Package as a `.vsix` (optional, for distribution)

```sh
npm install -g @vscode/vsce
cd vscode-mode
vsce package
code --install-extension crabir-0.1.0.vsix
```
