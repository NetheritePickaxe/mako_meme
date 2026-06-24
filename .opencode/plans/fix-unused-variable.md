# Fix unused_local_variable lint in meme_grid.dart

## Problem
CI analyze step failed with:
```
warning • The value of the local variable 'cols' isn't used. Try removing the variable or using it • lib/widgets/meme_grid.dart:30:15 • unused_local_variable
```

## Cause
Changed `SliverGridDelegateWithFixedCrossAxisCount` to `SliverGridDelegateWithMaxCrossAxisExtent`, which no longer needs `crossAxisCount`. The old code had a `LayoutBuilder` calculating `cols` based on window width, but this is now unused.

## Fix
Remove `LayoutBuilder` wrapper and the `cols` calculation from `meme_grid.dart`. The `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160)` automatically handles responsive column count based on available width.

## Changes
- `lib/widgets/meme_grid.dart`: Remove `LayoutBuilder`, remove `cols` variable, keep `GridView.builder` with the new grid delegate.
