const std = @import("std");
const sdl = @cImport(@cInclude("SDL.h"));
const CPU = @import("cpu.zig");
const process = std.process;

pub fn println(msg: []const u8) void {
    std.debug.print("{s}\n", .{msg});
}

var window: ?*sdl.SDL_Window = null;
var renderer: ?*sdl.SDL_Renderer = null;
var texture: ?*sdl.SDL_Texture = null;

var cpu: *CPU = undefined;

pub fn create_window() void {
    window = sdl.SDL_CreateWindow("CHIP-8z", sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED, 1024, 512, 0);
    if (window == null) {
        @panic("SDL Window Creation Failed!");
    }
}

const keymap: [16]c_int = [_]c_int{
    sdl.SDL_SCANCODE_X,
    sdl.SDL_SCANCODE_1,
    sdl.SDL_SCANCODE_2,
    sdl.SDL_SCANCODE_3,
    sdl.SDL_SCANCODE_Q,
    sdl.SDL_SCANCODE_W,
    sdl.SDL_SCANCODE_E,
    sdl.SDL_SCANCODE_A,
    sdl.SDL_SCANCODE_S,
    sdl.SDL_SCANCODE_D,
    sdl.SDL_SCANCODE_Z,
    sdl.SDL_SCANCODE_C,
    sdl.SDL_SCANCODE_4,
    sdl.SDL_SCANCODE_R,
    sdl.SDL_SCANCODE_F,
    sdl.SDL_SCANCODE_V,
};

pub fn init() void {
    println("CHIP-8z Started!");
    println("Initializing SDL!");

    if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) < 0) {
        @panic("SDL Initialization Failed!");
    }

    create_window();

    // Okay let's setup some basic rendering
    renderer = sdl.SDL_CreateRenderer(window, -1, 0);

    if (renderer == null) {
        var err = sdl.SDL_GetError();
        std.debug.print("{s}\n", .{err});

        @panic("SDL Renderer Initialization Failed!");
    }

    texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGBA8888, sdl.SDL_TEXTUREACCESS_STREAMING, 64, 32);
    if (texture == null) {
        @panic("SDL Texture Creation Failed!");
    }
}

pub fn deinit() void {
    sdl.SDL_DestroyWindow(window);
    window = null;

    println("Quitting SDL!");
    sdl.SDL_Quit();
    println("CHIP-8z Exitting!");
}

pub fn loadROM(filename: []const u8, system: *CPU) !void {
    var inputFile = try std.fs.cwd().openFile(filename, .{});
    defer inputFile.close();

    println("Loading ROM!");
    var size = try inputFile.getEndPos();
    std.debug.print("ROM File Size {}\n", .{size});
    var reader = inputFile.reader();

    var i: usize = 0;
    while (i < size) : (i += 1) {
        system.memory[i + 0x200] = try reader.readByte();
    }

    println("Loading ROM Succeeded!");
}

pub fn buildTexture(system: *CPU) void {
    var bytes: ?[*]u32 = null;
    var pitch: c_int = 0;
    _ = sdl.SDL_LockTexture(texture, null, @ptrCast([*c]?*anyopaque, &bytes), &pitch);

    var y: usize = 0;
    while (y < 32) : (y += 1) {
        var x: usize = 0;
        while (x < 64) : (x += 1) {
            bytes.?[y * 64 + x] = if (system.graphics[y * 64 + x] == 1) 0xFFFFFFFF else 0x000000FF;
        }
    }
    sdl.SDL_UnlockTexture(texture);
}

pub fn main() !void {
    const slow_factor = 1;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_it = try process.argsWithAllocator(allocator);
    _ = arg_it.skip();

    var filename = arg_it.next() orelse {
        println("No ROM file given!\n");
        return;
    };

    init();
    defer deinit();

    cpu = try allocator.create(CPU);
    try cpu.init();

    // Load a ROM
    try loadROM(filename, cpu);

    var keep_open = true;
    while (keep_open) {

        // virtual speed
        const DISPLAY_FREQUENCY = 60;
        const MACHINE_FREQUENCY = 700;
        const CYCLES_PER_LOOP = MACHINE_FREQUENCY / DISPLAY_FREQUENCY;

        // run CYCLES_PER_LOOP cycles
        for (0..CYCLES_PER_LOOP) |_| {
            try cpu.cycle();
        }
        // update timers (call 60 times per second)
        try cpu.update_timers();

        var e: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&e) > 0) {
            switch (e.type) {
                sdl.SDL_QUIT => keep_open = false,
                sdl.SDL_KEYDOWN => {
                    if (e.key.keysym.scancode == sdl.SDL_SCANCODE_ESCAPE) {
                        keep_open = false;
                    }

                    var i: usize = 0;
                    while (i < 16) : (i += 1) {
                        if (e.key.keysym.scancode == keymap[i]) {
                            cpu.keys[i] = 1;
                        }
                    }
                },
                sdl.SDL_KEYUP => {
                    var i: usize = 0;
                    while (i < 16) : (i += 1) {
                        if (e.key.keysym.scancode == keymap[i]) {
                            cpu.keys[i] = 0;
                        }
                    }
                },
                else => {},
            }
        }
        _ = sdl.SDL_RenderClear(renderer);

        buildTexture(cpu);

        var dest = sdl.SDL_Rect{ .x = 0, .y = 0, .w = 1024, .h = 512 };
        _ = sdl.SDL_RenderCopy(renderer, texture, null, &dest);
        _ = sdl.SDL_RenderPresent(renderer);

        std.time.sleep(1000 / DISPLAY_FREQUENCY * 1000 * 1000 * slow_factor);
    }
}
