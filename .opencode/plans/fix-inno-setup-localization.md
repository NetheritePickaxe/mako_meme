# Fix Inno Setup Chinese Localization - Path Bug

## Problem
CI build failed with:
```
Couldn't open include file "...tools\tools\Languages\ChineseSimplified.isl"
```

Note the **double `tools\`** in the path. The `.isl` file is at `tools/Languages/ChineseSimplified.isl`, but `setup.iss` is also inside `tools/`, so the relative path becomes `tools/tools/Languages/...`.

## Fix
Change `setup.iss` line 22 from:
```ini
Name: "chinesesimplified"; MessagesFile: "tools\Languages\ChineseSimplified.isl"
```
to:
```ini
Name: "chinesesimplified"; MessagesFile: "Languages\ChineseSimplified.isl"
```

The path is relative to `setup.iss`'s directory (`tools/`), so just `Languages\ChineseSimplified.isl`.

## Files to change
- `tools/setup.iss` — fix the MessagesFile path
