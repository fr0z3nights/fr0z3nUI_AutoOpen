## FAO ADDON TO DO LIST
- When a task is COMPLETED change the - to a +
- Do not remove anything from the list

```diff

# GUI

+   - 
+   - 
+   - 

# AutoOpen Tab (Items)

+   + Opening coodown text and input box
+       - bring the s in from the right so it looks cleaner make it white like the boxs text
+       - nove it a bit closer to the : of the text
+       - center the text and input box together on the tab, not just the input box

# Home Tab

+   - 
+   - 
+   - 

# Macros Tab

+   + Revert the change you made to the ACC/CHAR button it is not meant to look like that, move it down also
+   + the Hearth and Zone text display becomes a single line "Hearth, Zone" no titles
+       - it will sit above the other 3 rows of buttons next to the HS Hearth button
+       - the text will be Left aligned against the right side of the button
+       - its text box will be the length of the 3 buttons below it,
+       - its fonts largest size with be the height of the button next to it
+       - if it gets to long for its box (doubt it will happen [i was wrong]) the text should shrink to fit the box's length
+   - Increase the size of all buttons by 5%, keeping spacing between buttons (excluding Reload UI)

# Toggle Tab

+   - imagine the window split in two, ceenter the buttons on the left side and right of the window
+   - 
+   - 

# Addon File Structure

+    + fr0z3nUI_AutoOpen.lua (Core)

+       - 
+       - 
+       - 

+    + fr0z3nUI_AutoOpen.toc (Starter)

+       - 
+       - 
+       - 

+    + fr0z3nUI_AutoOpenHome.lua (Home TAB & Conetens)
+    + fr0z3nUI_AutoOpenHomeUI.lua (Home TAB & Conetens)

+       - keep when empty after split below I have plans for it
+       - 
+       - 

+    + fr0z3nUI_AutoOpenMacros.lua (Macros logic/helpers)
+    + fr0z3nUI_AutoOpenMacrosUI.lua (Macros tab UI)

+       - Keep macros-only code in these files (housing is in Home files)
+       - 
+       - 

+   + fr0z3nUI_AutoOpenXP--.lua (AutoOpen Item Database)
    
+       - 
+       - 
+       - 




```
## REMINDER FOR USER ONLY BELOW THIS LINE DO NOT READ BEYOND THIS POINT

- Macro simplification (FAO Macros)









