const std = @import("std");
const testing = std.testing;

var plugin_type: [1]C.GType = [1]C.GType{0};

const C = @cImport({
    @cInclude("nautilus/nautilus-extension.h");
});

export fn nautilus_module_initialize(module: [*c]C.GTypeModule) void {
    const info = C.GTypeInfo{
        .class_size = @sizeOf(C.GObjectClass),
        .base_init = null,
        .base_finalize = null,
        .class_init = null,
        .class_finalize = null,
        .class_data = null,
        .instance_size = @sizeOf(C.GObject),
        .n_preallocs = 0,
        .instance_init = null,
        .value_table = null,
    };

    const ifaceInfo = C.GInterfaceInfo{
        .interface_init = iface_init,
        .interface_finalize = null,
        .interface_data = null,
    };

    plugin_type[0] = C.g_type_module_register_type(module, C.G_TYPE_OBJECT, "XdgTerminalNautilusPlugin", &info, 0);
    C.g_type_module_add_interface(module, plugin_type[0], C.nautilus_menu_provider_get_type(), &ifaceInfo);
}

fn iface_init(g_iface: ?*anyopaque, iface_data: C.gpointer) callconv(.C) void {
    _ = iface_data;

    const iface: ?*C.NautilusMenuProviderInterface = @ptrCast(@alignCast(g_iface));
    if (iface) |i| {
        i.get_background_items = get_background_items;
    }
}

fn get_background_items(provider: ?*C.NautilusMenuProvider, item: ?*C.NautilusFileInfo) callconv(.C) [*c]C.GList {
    _ = provider;
    var result: [*c]C.GList = null;

    var menu_item = C.nautilus_menu_item_new("xdg-open-terminal-open-in-dir", "Open terminal here", null, null);

    const location = C.nautilus_file_info_get_location(item);

    _ = C.g_signal_connect_object(
        menu_item,
        "activate",
        @as(C.GCallback, @ptrCast(@alignCast(&open_terminal_called))),
        location,
        std.zig.c_translation.cast(C.GConnectFlags, @as(c_int, 0)),
    );
    result = C.g_list_prepend(result, menu_item);
    return result;
}

fn open_terminal_called(self: [*c]C.NautilusMenuItem, user_data: C.gpointer) callconv(.C) void {
    _ = self;

    if (@as(?*C.GFile, @ptrCast(user_data))) |location| {
        const direct_allocator = std.heap.c_allocator;

        const path = C.g_file_get_path(location);
        spawn_in(direct_allocator, path) catch |e| {
            std.debug.print("failed to spawn {?}", .{e});
        };
    }
}

fn spawn_in(allocator: std.mem.Allocator, path: [*:0]u8) !void {
    const shell = try std.process.getEnvVarOwned(allocator, "SHELL");

    const string = try std.fmt.allocPrint(
        allocator,
        "cd {s} && {s}",
        .{ path, shell },
    );
    var child_process = std.ChildProcess.init(&[_][]const u8{ "xdg-terminal-exec", string }, allocator);
    try child_process.spawn();

    allocator.free(string);
}

export fn nautilus_module_shutdown() void {}

export fn nautilus_module_list_types(types: [*c][*c]const C.GType, num_types: [*c]c_int) void {
    types.* = @ptrCast(&plugin_type);
    num_types.* = 1;
}
