const std = @import("std");
const testing = std.testing;

const c = @import("c.zig");

/// Map an M3Result to the matching Error value.
fn mapError(result: c.M3Result) Error!void {
    @setEvalBranchQuota(50000);
    const match_list = comptime get_results: {
        const Declaration = std.builtin.TypeInfo.Declaration;
        var result_values: []const [2][]const u8 = &[0][2][]const u8{};
        for (std.meta.declarations(c)) |decl| {
            const d: Declaration = decl;
            if (std.mem.startsWith(u8, d.name, "m3Err_")) {
                if (!std.mem.eql(u8, d.name, "m3Err_none")) {
                    var error_name = d.name[("m3Err_").len..];

                    error_name = get: for (std.meta.fieldNames(Error)) |f| {
                        if (std.ascii.eqlIgnoreCase(error_name, f)) {
                            break :get f;
                        }
                    } else {
                        @compileError("Failed to find matching error for code " ++ d.name);
                    };

                    result_values = result_values ++ [1][2][]const u8{[2][]const u8{ d.name, error_name }};
                }
            }
        }
        break :get_results result_values;
    };

    if (result == c.m3Err_none) return;
    inline for (match_list) |pair| {
        if (result == @field(c, pair[0])) return @field(Error, pair[1]);
    }
    unreachable;
}

const Error = error{
    TypeListOverflow,
    MallocFailed,
    IncompatibleWasmVersion,
    WasmMalformed,
    MisorderedWasmSection,
    WasmUnderrun,
    WasmOverrun,
    WasmMissingInitExpr,
    LebOverflow,
    MissingUtf8,
    WasmSectionUnderrun,
    WasmSectionOverrun,
    InvalidTypeId,
    TooManyMemorySections,
    ModuleAlreadyLinked,
    FunctionLookupFailed,
    FunctionImportMissing,
    MalformedFunctionSignature,
    NoCompiler,
    UnknownOpcode,
    FunctionStackOverflow,
    FunctionStackUnderrun,
    MallocFailedCodePage,
    SettingImmutableGlobal,
    OptimizerFailed,
    MissingCompiledCode,
    WasmMemoryOverflow,
    GlobalMemoryNotAllocated,
    GlobaIndexOutOfBounds,
    ArgumentCountMismatch,
    TrapOutOfBoundsMemoryAccess,
    TrapDivisionByZero,
    TrapIntegerOverflow,
    TrapIntegerConversion,
    TrapIndirectCallTypeMismatch,
    TrapTableIndexOutOfRange,
    TrapTableElementIsNull,
    TrapExit,
    TrapAbort,
    TrapUnreachable,
    TrapStackOverflow,
};

pub const Runtime = struct {
    impl: c.IM3Runtime,

    pub fn deinit(this: Runtime) callconv(.Inline) void {
        c.m3_FreeRuntime(this.impl);
    }
    pub fn getMemory(this: Runtime, memory_index: u32) callconv(.Inline) ?[]u8 {
        var size: u32 = 0;
        var mem = c.m3_GetMemory(this.impl, &size, memory_index);
        if (mem) |valid| {
            return valid[0..@intCast(usize, size)];
        }
        return null;
    }
    pub fn getUserData(this: Runtime) callconv(.Inline) ?*c_void {
        return c.m3_GetUserData(this.impl);
    }

    pub fn loadModule(this: Runtime, module: Module) callconv(.Inline) !void {
        try mapError(c.m3_LoadModule(this.impl, module.impl));
    }

    pub fn findFunction(this: Runtime, function_name: [:0]const u8) callconv(.Inline) !Function {
        var func = Function{ .impl = undefined };
        try mapError(c.m3_FindFunction(&func.impl, this.impl, function_name.ptr));
        return func;
    }
    pub fn printRuntimeInfo(this: Runtime) callconv(.Inline) void {
        c.m3_PrintRuntimeInfo(this.impl);
    }
    pub const ErrorInfo = c.M3ErrorInfo;
    pub fn getErrorInfo(this: Runtime) callconv(.Inline) ErrorInfo {
        var info: ErrorInfo = undefined;
        c.m3_GetErrorInfo(this.impl, &info);
        return info;
    }
    fn span(strz: ?[*:0]const u8) callconv(.Inline) []const u8 {
        if (strz) |s| return std.mem.span(s);
        return "nullptr";
    }
    pub fn printError(this: Runtime) callconv(.Inline) void {
        var info = this.getErrorInfo();
        this.resetErrorInfo();
        std.log.err("Wasm3 error: {s} @ {s}:{d}\n", .{ span(info.message), span(info.file), info.line });
    }
    pub fn resetErrorInfo(this: Runtime) callconv(.Inline) void {
        c.m3_ResetErrorInfo(this.impl);
    }
};

pub const Function = struct {
    impl: c.IM3Function,

    pub fn getArgCount(this: Function) callconv(.Inline) u32 {
        return c.m3_GetArgCount(this.impl);
    }
    pub fn getRetCount(this: Function) callconv(.Inline) u32 {
        return c.m3_GetRetCount(this.impl);
    }
    pub fn getArgType(this: Function, idx: u32) callconv(.Inline) c.M3ValueType {
        return c.m3_GetArgType(this.impl, idx);
    }
    pub fn getRetType(this: Function, idx: u32) callconv(.Inline) c.M3ValueType {
        return c.m3_GetRetType(this.impl, idx);
    }
    /// Call a function, using a provided tuple for arguments.
    /// TYPES ARE NOT VALIDATED. Be careful
    /// TDOO: Test this! Zig has weird symbol export issues with wasm right now,
    ///       so I can't verify that arguments or return values are properly passes!
    pub fn call(this: Function, comptime RetType: type, args: anytype) callconv(.Inline) !RetType {
        if (this.getRetCount() > 1) {
            return error.TooManyReturnValues;
        }

        const ArgsType = @TypeOf(args);
        if (@typeInfo(ArgsType) != .Struct) {
            @compileError("Expected tuple or struct argument, found " ++ @typeName(ArgsType));
        }
        const fields_info = std.meta.fields(ArgsType);

        const count = fields_info.len;
        comptime var ptr_i: comptime_int = 0;
        const num_pointers = comptime ptr_count: {
            var num_ptrs: comptime_int = 0;
            var i: comptime_int = 0;
            inline while (i < count) : (i += 1) {
                const ArgType = @TypeOf(args[i]);
                if (comptime isNativePtr(ArgType) or comptime isOptNativePtr(ArgType)) {
                    num_ptrs += 1;
                }
            }
            break :ptr_count num_ptrs;
        };
        var pointer_values: [num_pointers]u32 = undefined;

        var arg_arr: [count]?*const c_void = undefined;
        comptime var i: comptime_int = 0;
        inline while (i < count) : (i += 1) {
            const ArgType = @TypeOf(args[i]);
            if (comptime isNativePtr(ArgType) or comptime isOptNativePtr(ArgType)) {
                pointer_values[ptr_i] = toLocalPtr(args[i]);
                arg_arr[i] = @ptrCast(?*const c_void, &pointer_values[ptr_i]);
                ptr_i += 1;
            } else {
                arg_arr[i] = @ptrCast(?*const c_void, &args[i]);
            }
        }
        try mapError(c.m3_Call(this.impl, @intCast(u32, count), if (count == 0) null else &arg_arr));

        if (RetType == void) return;

        const Extensions = struct {
            pub extern fn wasm3_addon_get_runtime_mem_ptr(rt: c.IM3Runtime) [*c]u8;
            pub extern fn wasm3_addon_get_fn_rt(func: c.IM3Function) c.IM3Runtime;
        };

        const runtime_ptr = Extensions.wasm3_addon_get_fn_rt(this.impl);
        var return_data_buffer: u64 = undefined;
        var return_ptr: *c_void = @ptrCast(*c_void, &return_data_buffer);
        try mapError(c.m3_GetResults(this.impl, 1, &[1]?*c_void{return_ptr}));

        if (comptime isNativePtr(RetType) or comptime isOptNativePtr(RetType)) {
            const mem_ptr = Extensions.wasm3_addon_get_runtime_mem_ptr(runtime_ptr);
            return fromLocalPtr(
                RetType,
                @ptrCast(*u32, @alignCast(@alignOf(u32), return_ptr)).*,
                @ptrToInt(mem_ptr),
            );
        }
        switch (RetType) {
            i8, i16, i32, i64, u8, u16, u32, u64, f32, f64 => {
                return @ptrCast(*RetType, @alignCast(@alignOf(RetType), return_ptr)).*;
            },
            else => {},
        }
        @compileError("Invalid WebAssembly return type " ++ @typeName(RetType) ++ "!");
    }
};

fn isNativePtr(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Struct => @hasDecl(T, "_is_wasm3_local_ptr"),
        else => false,
    };
}

fn isOptNativePtr(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Optional => |opt| isNativePtr(opt.child),
        else => false,
    };
}

pub fn NativePtr(comptime T: type) type {
    comptime {
        switch (T) {
            i8, i16, i32, i64 => {},
            u8, u16, u32, u64 => {},
            else => @compileError("Invalid type for a NativePtr. Must be an integer!"),
        }
    }
    return struct {
        const _is_wasm3_local_ptr = true;
        pub const Base = T;
        local_heap: usize,
        host_ptr: *T,
        const Self = @This();

        pub fn localPtr(this: Self) callconv(.Inline) u32 {
            return @intCast(u32, @ptrToInt(this.host_ptr) - this.local_heap);
        }
        pub fn write(this: Self, val: T) callconv(.Inline) void {
            std.mem.writeIntLittle(T, std.mem.asBytes(this.host_ptr), val);
        }
        pub fn read(this: Self) callconv(.Inline) T {
            return std.mem.readIntLittle(T, std.mem.asBytes(this.host_ptr));
        }
        fn offsetBy(this: Self, offset: i64) callconv(.Inline) *T {
            return @intToPtr(*T, get_ptr: {
                if (offset > 0) {
                    break :get_ptr @ptrToInt(this.host_ptr) + @intCast(usize, offset);
                } else {
                    break :get_ptr @ptrToInt(this.host_ptr) - @intCast(usize, -offset);
                }
            });
        }
        /// Offset is in bytes, NOT SAFETY CHECKED.
        pub fn writeOffset(this: Self, offset: i64, val: T) callconv(.Inline) void {
            std.mem.writeIntLittle(T, std.mem.asBytes(this.offsetBy(offset)), val);
        }
        /// Offset is in bytes, NOT SAFETY CHECKED.
        pub fn readOffset(this: Self, offset: i64) callconv(.Inline) T {
            std.mem.readIntLittle(T, std.mem.asBytes(this.offsetBy(offset)));
        }
        pub usingnamespace if (T == u8)
            struct {
                /// NOT SAFETY CHECKED.
                pub fn slice(this: Self, len: u32) callconv(.Inline) []T {
                    return @ptrCast([*]u8, this.host_ptr)[0..@intCast(usize, len)];
                }
            }
        else
            struct {};
    };
}

fn fromLocalPtr(comptime T: type, localptr: u32, local_heap: usize) T {
    if (comptime isOptNativePtr(T)) {
        const Child = std.meta.Child(T);
        if (localptr == 0) return null;
        return Child{
            .local_heap = local_heap,
            .host_ptr = @intToPtr(*Child.Base, local_heap + @intCast(usize, localptr)),
        };
    } else if (comptime isNativePtr(T)) {
        std.debug.assert(localptr != 0);
        return T{
            .local_heap = local_heap,
            .host_ptr = @intToPtr(*T.Base, local_heap + @intCast(usize, localptr)),
        };
    } else {
        @compileError("Expected a NativePtr or a ?NativePtr");
    }
}

fn toLocalPtr(nativeptr: anytype) u32 {
    const T = @TypeOf(nativeptr);
    if (comptime isOptNativePtr(T)) {
        if (nativeptr) |np| {
            const lp = np.localPtr();
            std.debug.assert(lp != 0);
            return lp;
        } else return 0;
    } else if (comptime isNativePtr(T)) {
        const lp = nativeptr.localPtr();
        std.debug.assert(lp != 0);
        return lp;
    } else {
        @compileError("Expected a NativePtr or a ?NativePtr");
    }
}

pub const Module = struct {
    impl: c.IM3Module,

    pub fn deinit(this: Module) void {
        c.m3_FreeModule(this.impl);
    }

    fn mapTypeToChar(comptime T: type) u8 {
        switch (T) {
            void => return 'v',
            u32, i32 => return 'i',
            u64, i64 => return 'I',
            f32 => return 'f',
            f64 => return 'F',
            else => {},
        }
        if (comptime isNativePtr(T) or comptime isOptNativePtr(T)) {
            return '*';
        }
        switch (@typeInfo(T)) {
            .Pointer => |ptrti| {
                if (ptrti.size == .One) {
                    @compileError("Please use a wasm3.NativePtr instead of raw pointers!");
                }
            },
        }
        @compileError("Invalid type " ++ @typeName(T) ++ " for WASM interop!");
    }

    pub fn linkWasi(this: Module) !void {
        return mapError(c.m3_LinkWASI(this.impl));
    }

    /// Links all functions in a struct to the module.
    /// library_name: the name of the library this function should belong to.
    /// library: a struct containing functions that should be added to the module.
    ///          See linkRawFunction(...) for information about valid function signatures.
    /// userdata: A single-item pointer passed to the function as the first argument when called.
    ///           Not accessible from within wasm, handled by the interpreter.
    ///           If you don't want userdata, pass a void literal {}.
    pub fn linkLibrary(this: Module, library_name: [:0]const u8, comptime library: type, userdata: anytype) !void {
        comptime const decls = std.meta.declarations(library);
        inline for (decls) |decl| {
            if (decl.is_pub) {
                switch (decl.data) {
                    .Fn => |fninfo| {
                        const fn_name_z = comptime get_name: {
                            var name_buf: [decl.name.len:0]u8 = undefined;
                            std.mem.copy(u8, &name_buf, decl.name);
                            break :get_name name_buf;
                        };
                        try this.linkRawFunction(library_name, &fn_name_z, @field(library, decl.name), userdata);
                    },
                    else => continue,
                }
            }
        }
    }

    /// Links a native function into the module.
    /// library_name: the name of the library this function should belong to.
    /// function_name: the name the function should have in module-space.
    /// function: a zig function (not function pointer!).
    ///           Valid argument and return types are:
    ///             i32, u32, i64, u64, f32, f64, void, and pointers to basic types.
    ///           Userdata, if provided, is the first argument to the function.
    /// userdata: A single-item pointer passed to the function as the first argument when called.
    ///           Not accessible from within wasm, handled by the interpreter.
    ///           If you don't want userdata, pass a void literal {}.
    pub fn linkRawFunction(this: Module, library_name: [:0]const u8, function_name: [:0]const u8, comptime function: anytype, userdata: anytype) !void {
        errdefer {
            std.log.err("Failed to link proc {s}.{s}!\n", .{ library_name, function_name });
        }
        comptime const has_userdata = @TypeOf(userdata) != void;
        comptime validate_userdata: {
            if (has_userdata) {
                switch (@typeInfo(@TypeOf(userdata))) {
                    .Pointer => |ptrti| {
                        if (ptrti.size == .One) {
                            break :validate_userdata;
                        }
                    },
                    else => {},
                }
                @compileError("Expected a single-item pointer for the userdata, got " ++ @typeName(@TypeOf(userdata)));
            }
        }
        const UserdataType = @TypeOf(userdata);
        const sig = comptime generate_signature: {
            switch (@typeInfo(@TypeOf(function))) {
                .Fn => |fnti| {
                    const sub_data = if (has_userdata) 1 else 0;
                    var arg_str: [fnti.args.len + 3 - sub_data:0]u8 = undefined;
                    arg_str[0] = mapTypeToChar(fnti.return_type orelse void);
                    arg_str[1] = '(';
                    arg_str[arg_str.len - 1] = ')';
                    for (fnti.args[sub_data..]) |arg, i| {
                        if (arg.is_generic) {
                            @compileError("WASM does not support generic arguments to native functions!");
                        }
                        arg_str[2 + i] = mapTypeToChar(arg.arg_type.?);
                    }
                    break :generate_signature arg_str;
                },
                else => @compileError("Expected a function, got " ++ @typeName(@TypeOf(function))),
            }
            unreachable;
        };
        const lambda = struct {
            pub fn l(rt: c.IM3Runtime, sp: [*c]u64, _mem: ?*c_void, arg_userdata: ?*c_void) callconv(.C) ?*const c_void {
                comptime var type_arr: []const type = &[0]type{};
                if (has_userdata) {
                    type_arr = type_arr ++ @as([]const type, &[1]type{UserdataType});
                }
                var mem = @ptrToInt(_mem);
                var stack = @ptrToInt(sp);
                const stride = @sizeOf(u64) / @sizeOf(u8);

                switch (@typeInfo(@TypeOf(function))) {
                    .Fn => |fnti| {
                        const RetT = fnti.return_type orelse void;

                        const return_pointer = comptime isNativePtr(RetT) or comptime isOptNativePtr(RetT);

                        const RetPtr = if (RetT == void) void else if (return_pointer) *u32 else *RetT;
                        var ret_val: RetPtr = undefined;
                        if (RetT != void) {
                            ret_val = @intToPtr(RetPtr, stack);
                        }

                        const sub_data = if (has_userdata) 1 else 0;
                        inline for (fnti.args[sub_data..]) |arg, i| {
                            if (arg.is_generic) unreachable;

                            type_arr = type_arr ++ @as([]const type, &[1]type{arg.arg_type.?});
                        }

                        var args: std.meta.Tuple(type_arr) = undefined;

                        comptime var idx: usize = 0;
                        if (has_userdata) {
                            args[idx] = @ptrCast(UserdataType, @alignCast(@alignOf(std.meta.Child(UserdataType)), arg_userdata));
                            idx += 1;
                        }
                        inline for (fnti.args[sub_data..]) |arg, i| {
                            if (arg.is_generic) unreachable;

                            const ArgT = arg.arg_type.?;

                            if (comptime isNativePtr(ArgT) or comptime isOptNativePtr(ArgT)) {
                                args[idx] = fromLocalPtr(ArgT, @intToPtr(*u32, stack).*, mem);
                            } else {
                                args[idx] = @intToPtr(*ArgT, stack).*;
                            }
                            idx += 1;
                            stack += stride;
                        }

                        if (RetT == void) {
                            @call(.{ .modifier = .always_inline }, function, args);
                        } else {
                            const returned_value = @call(.{ .modifier = .always_inline }, function, args);
                            if (return_pointer) {
                                ret_val.* = toLocalPtr(returned_value);
                            } else {
                                ret_val.* = returned_value;
                            }
                        }

                        return c.m3Err_none;
                    },
                    else => unreachable,
                }
            }
        }.l;
        try mapError(c.m3_LinkRawFunctionEx(this.impl, library_name, function_name, @as([*]const u8, &sig), lambda, if (has_userdata) userdata else null));
    }
};

pub const Environment = struct {
    impl: c.IM3Environment,

    pub fn init() callconv(.Inline) Environment {
        return .{ .impl = c.m3_NewEnvironment() };
    }
    pub fn deinit(this: Environment) callconv(.Inline) void {
        c.m3_FreeEnvironment(this.impl);
    }
    pub fn createRuntime(this: Environment, stack_size: u32, userdata: ?*c_void) callconv(.Inline) Runtime {
        return .{ .impl = c.m3_NewRuntime(this.impl, stack_size, userdata) };
    }
    pub fn parseModule(this: Environment, wasm: []const u8) callconv(.Inline) !Module {
        var mod = Module{ .impl = undefined };
        var res = c.m3_ParseModule(this.impl, &mod.impl, wasm.ptr, @intCast(u32, wasm.len));
        try mapError(res);
        return mod;
    }
};

pub fn yield() callconv(.Inline) !void {
    return mapError(c.m3_Yield());
}
pub fn printM3Info() callconv(.Inline) void {
    c.m3_PrintM3Info();
}
pub fn printProfilerInfo() callconv(.Inline) void {
    c.m3_PrintProfilerInfo();
}

pub usingnamespace if (std.Target.current.abi.isGnu() and std.Target.current.os.tag != .windows)
    struct {
        // Glibc's getrandom is namespaced, but for some reason m3 is building without that namespace.
        export fn getrandom(buf: [*c]u8, len: usize, flags: c_uint) i64 {
            std.os.getrandom(buf[0..len]) catch return 0;
            return @intCast(i64, len);
        }
    }
else
    struct {};
