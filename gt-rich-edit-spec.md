Here is a technical specification and architecture blueprint designed specifically for an AI agent operating a **Glamorous Toolkit (GT)** instance.

---

```markdown
# TECHNICAL SPECIFICATION: Hybrid Direct-Manipulation Text-Widget Interface in Glamorous Toolkit

## 1. System Objective
Build an inline, projectional, text-editor-like surface in Glamorous Toolkit (GT) where plain text/markup dynamically swaps between raw string representations and rich, interactive visual widgets based on cursor locality, user interaction, and domain state.

This system combines:
- **Obsidian-style cursor locality rules**: Hiding syntax tokens (e.g., `**bold**`, `[ ]`, `https://...`) or collapsing blocks into rendered elements when the cursor is outside the AST node, and expanding back to raw editable text when the cursor enters.
- **Bret Victor / VS Code style inline controls**: Replacing inline tokens (e.g., `#FF0000`, `2026-08-28`) with interactive UI widgets (color pickers, date pickers, sliders) that directly mutate the underlying buffer string on change.
- **GT Moldable Capabilities**: Transforming inline code references or objects into live Smalltalk inspector widgets or embedded executable UI cards.

---

## 2. Core Architecture & GT Abstractions

GT's graphical stack (**Bloc**) and text framework (**Sparta / BrRope / GtCoder**) run on a single unified rendering tree. Text in GT is represented as a `BlRope` augmented with **Text Attributes**. You must leverage this architecture rather than building custom canvas overlays.

### Key Classes to Use & Extend
1. **`GtTextualCoderEditorElement` / `BrEditor`**: The core text editing view.
2. **`GtCoderCodeStyler`**: The class responsible for parsing text and attaching attributes (`BrTextAttribute`) to ranges of text asynchronously as the user types.
3. **`BrTextAdornmentDynamicAttribute`**: A text attribute that hides or augments a range of characters and renders an arbitrary `BlElement` (a button, widget, or full GT inspector) inline at that position.
4. **`BrTextHideAttribute`**: An attribute used to visually collapse ranges of characters (such as markdown delimiters `**` or `[x]`) to zero width.
5. **`GtTextualCoderView` / `BrEditorElement` Event Handlers**: To intercept cursor movements (`GtEditorCursorMovedEvent` / `BrTextEditorCursorElement`) and selection changes.

---

## 3. Implementation Workflow

### Step 1: Define the AST / Token Model
Do not perform raw regex matches directly inside the UI rendering loop. Use a SmaCC parser or GT's `GtPatternString` / PetitParser to produce an AST with concrete source intervals (`start` and `stop` character offsets).

Every interactive token must evaluate to a domain object:
- `MarkdownCheckboxToken` (`start: 12, stop: 15, checked: false`)
- `ColorCodeToken` (`start: 45, stop: 52, hex: '#FF0000'`)
- `MarkdownHeaderToken` (`start: 0, stop: 8, level: 1`)

### Step 2: Implement the Custom Styler (`GtCoderStyler`)
Create a subclass of `GtCoderStyler` (e.g., `GtHybridProjectionStyler`) that overrides `privateStyle: aText`.

```smalltalk
GtHybridProjectionStyler >> privateStyle: aRopedText
    | ast cursorPosition |
    cursorPosition := self currentCursorPosition.
    ast := self parseText: aRopedText.

    ast tokensDo: [ :aToken |
        (aToken containsIndex: cursorPosition)
            ifTrue: [ self styleAsRawSource: aToken on: aRopedText ]
            ifFalse: [ self styleAsRenderedWidget: aToken on: aRopedText ] ].

    ^ aRopedText

```

### Step 3: Projection Rules & Widget Injection

#### Rule A: Obsidian-Style Locality (Markdown / Bold / Headers / Code Blocks)

* **When Cursor IS NOT on the AST node:**
1. Add `BrTextHideAttribute new` to the token boundary delimiters (e.g., the `**` on both sides).
2. Add `BrTextFontWeightAttribute bold` (or font size changes) to the inner text range.


* **When Cursor IS on the AST node:**
1. Remove `BrTextHideAttribute`. Reveal raw syntax tags (`**bold text**`) in dim gray (`BrTextForegroundAttribute color: Color gray`).



#### Rule B: Inline Control Mutators (Checkboxes, Color Pickers, Sliders)

* **When Cursor IS NOT on the AST node:**
1. Hide the raw text range (e.g., `[ ]`) using `BrTextHideAttribute`.
2. Attach a `BrTextAdornmentDynamicAttribute` with `beReplace` or `beAppend`.
3. Inside the attribute's `stencil:` block, construct a live `BlElement`:



```smalltalk
"Example: Rendering a live clickable checkbox over '[ ]' or '[x]'"
attribute := BrTextAdornmentDynamicAttribute new stencil: [
    | checkboxElement |
    checkboxElement := BrCheckbox new
        look: BrLook;
        checked: aToken isChecked;
        when: BrCheckboxToggled do: [ :anEvent |
            "Mutate underlying rope buffer directly"
            self
                replaceTextRange: aToken sourceInterval
                with: (anEvent isChecked ifTrue: [ '[x]' ] ifFalse: [ '[ ]' ])
                inEditor: self editor ].
    checkboxElement
].
aRopedText addAttribute: attribute from: aToken start to: aToken stop.

```

#### Rule C: VS Code Style Inline Color / Date Pickers

* Hide the hex string `#FF0000`.
* Append a tiny `BlElement` swatch showing color `#FF0000`.
* On click, spawn a `GtPopover` containing a GT Color Palette picker.
* Selecting a color executes `aTextEditor inserter replace: aToken interval with: newHex`.

---

## 4. Cursor Locality Listener

To trigger restyling instantly when the cursor moves without waiting for text edits:

1. Register an event listener on the `BrTextEditor` for cursor movement:
```smalltalk
anEditor when: BrTextEditorCursorMovedEvent do: [ :anEvent |
    "Re-evaluate styler for affected AST nodes"
    anEditor requestStyle
].

```


2. Optimise restyling: Only re-evaluate adornments for AST nodes whose locality status (`containsCursor`) changed between the previous and current cursor positions.

---

## 5. Execution Script for the GT Agent

Agent, execute the following steps in Pharo/GT to verify and build a prototype editor instance:

1. **Create the Test Class:** Create a workspace package `HybridEditor-Core` and a styler subclass `GtHybridProjectionStyler`.
2. **Build a Playground Demonstrator:** Run the following snippet in GT to test dynamic text adornments on a live text editor element:

```smalltalk
| text editor element styler |

text := '[ ] Turn this into a checkbox' asRopedText.

"Attach a dynamic widget replacing characters 1 to 3 ([ ])"
text
    addAttribute: (BrTextAdornmentDynamicAttribute new stencil: [
        BrCheckbox new
            margin: (BlInsets right: 5);
            when: BrCheckboxToggled do: [ :evt |
                InformativeTextNotification signal: 'Toggled: ', evt isChecked printString ]
    ])
    from: 1
    to: 3.

editor := BrTextEditorModel new.
editor text: text.

element := BrEditorElement new.
element editor: editor.
element constraintsDo: [ :c |
    c horizontal matchParent.
    c vertical matchParent ].

element

```

3. **Verify:** Ensure the checkbox renders as a true `BlElement` within the text flow, wrapped inside GT's single rendering tree, and that event handlers successfully receive click interactions.

```

---

<ElicitationsGroup message="Next steps for implementation:">

  <Elicitation label="Generate Smalltalk code for a full SmaCC parser integration with this styler" query="Provide the full Pharo/GT Smalltalk code integrating a SmaCC parser with GtCoderStyler for Obsidian-style live preview."/>

  <Elicitation label="Show how to embed a live GT Inspector as an inline text adornment" query="Show how to embed a live GT Inspector as a BrTextAdornmentDynamicAttribute inside a GT text buffer."/>

</ElicitationsGroup>

```
