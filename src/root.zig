const app_mod = @import("core/app.zig");
pub const Application = app_mod.Application;
pub const Renderer    = app_mod.Renderer;

// Accessibility
const node_mod    = @import("accessibility/node.zig");
pub const AccessNode = node_mod.AccessNode;
pub const Role       = node_mod.Role;
pub const State      = node_mod.State;

// Style
pub const Color            = @import("style/color.zig").Color;
pub const Theme            = @import("style/theme.zig").Theme;
pub const Font             = @import("style/font.zig").Font;
pub const Style            = @import("style/style.zig").Style;
pub const Stylesheet       = @import("style/stylesheet.zig").Stylesheet;
const pseudo_mod           = @import("style/pseudo.zig");
pub const PseudoState      = pseudo_mod.PseudoState;
pub const PseudoStateTag   = pseudo_mod.PseudoStateTag;
pub const WidgetStylesheet = pseudo_mod.WidgetStylesheet;

// Events
pub const Event                = @import("events/event.zig").Event;
pub const KeyCode              = @import("events/event.zig").KeyCode;
pub const Modifiers            = @import("events/event.zig").Modifiers;
pub const ImeCompositionEvent  = @import("events/event.zig").ImeCompositionEvent;

// Layout
pub const Rect        = @import("layout/geometry.zig").Rect;
pub const Point       = @import("layout/geometry.zig").Point;
pub const Size        = @import("layout/geometry.zig").Size;
pub const Margin      = @import("layout/geometry.zig").Margin;
pub const BoxLayout   = @import("layout/box.zig").BoxLayout;
pub const Direction   = @import("layout/box.zig").Direction;
pub const GridLayout  = @import("layout/grid.zig").GridLayout;
pub const FlowLayout  = @import("layout/flow.zig").FlowLayout;

// Signals
pub fn Signal(comptime T: type) type { return @import("signals/signal.zig").Signal(T); }
pub fn Property(comptime T: type) type { return @import("signals/property.zig").Property(T); }
pub fn Computed(comptime T: type) type { return @import("signals/computed.zig").Computed(T); }

// Core
pub const Tween        = @import("core/animation.zig").Tween;
pub const FocusManager = @import("core/focus.zig").FocusManager;
pub const Animated      = @import("core/animator.zig").Animated;
pub const AnimatedColor = @import("core/animator.zig").AnimatedColor;
pub const Easing        = @import("core/animator.zig").Easing;

// Builder DSL
const builder_mod = @import("core/builder.zig");
pub const WidgetTag  = builder_mod.WidgetTag;
pub const WidgetType = builder_mod.WidgetType;
pub const ui         = builder_mod.ui;

// Graphics
pub const Image = @import("graphics/image.zig").Image;

// Widgets
pub const Label       = @import("widgets/label.zig").Label;
pub const Button      = @import("widgets/button.zig").Button;
pub const ButtonStyle = @import("widgets/button.zig").ButtonStyle;
pub const TextField   = @import("widgets/text_field.zig").TextField;
pub const TextArea    = @import("widgets/text_area.zig").TextArea;
pub const Container   = @import("widgets/container.zig").Container;
pub const Checkbox    = @import("widgets/checkbox.zig").Checkbox;
pub const Slider      = @import("widgets/slider.zig").Slider;
pub const ProgressBar = @import("widgets/progress_bar.zig").ProgressBar;
pub const TabView     = @import("widgets/tab_view.zig").TabView;
pub const ScrollArea  = @import("widgets/scroll_area.zig").ScrollArea;
pub const ListView    = @import("widgets/list_view.zig").ListView;
pub const DataSource  = @import("widgets/list_view.zig").DataSource;
pub const DropDown    = @import("widgets/dropdown.zig").DropDown;
pub const Tooltip     = @import("widgets/tooltip.zig").Tooltip;
pub const Dialog      = @import("widgets/dialog.zig").Dialog;
pub const MenuItem    = @import("widgets/menu.zig").MenuItem;
pub const Menu        = @import("widgets/menu.zig").Menu;
pub const NumberInput = @import("widgets/number_input.zig").NumberInput;
pub const TreeView    = @import("widgets/tree_view.zig").TreeView;
pub const TreeNode    = @import("widgets/tree_view.zig").TreeNode;
pub const DatePicker  = @import("widgets/date_picker.zig").DatePicker;

// File dialogs
const file_dialog_mod  = @import("platform/file_dialog.zig");
pub const FileFilter      = file_dialog_mod.FileFilter;
pub const FileDialogOptions = file_dialog_mod.FileDialogOptions;
pub const openFile    = file_dialog_mod.openFile;
pub const saveFile    = file_dialog_mod.saveFile;
pub const openFolder  = file_dialog_mod.openFolder;
