const std = @import("std");

/// Language Capabilities - Defines what features a language supports
/// Used for validation, feature mapping, and compatibility checking
pub const Capabilities = struct {
    name: []const u8,
    version: ?[]const u8 = null,

    // ============ TYPE SYSTEM ============
    types: TypeSystem = .{},

    // ============ CONCURRENCY ============
    concurrency: Concurrency = .{},

    // ============ MEMORY ============
    memory: Memory = .{},

    // ============ FUNCTIONS ============
    functions: Functions = .{},

    // ============ CONTROL FLOW ============
    control: ControlFlow = .{},

    // ============ MODULES ============
    modules: Modules = .{},

    // ============ METAPROGRAMMING ============
    meta: Metaprogramming = .{},

    // ============ RUNTIME ============
    runtime: Runtime = .{},

    // ============ PASSTHROUGH ============
    /// Features that can be preserved as-is if target doesn't support them
    /// These don't affect runtime behavior, so they're safe to ignore
    passthrough: Passthrough = .{},

    pub const Passthrough = struct {
        // Comments and documentation
        comments: bool = true, // Can preserve comments
        doc_comments: bool = true, // Can preserve doc strings

        // Type annotations (in dynamic languages)
        type_hints: bool = false, // Python type hints, TS types

        // Decorators/attributes that are metadata-only
        annotations: bool = false, // @deprecated, #[allow], etc.

        // Compiler directives
        pragmas: bool = false, // #pragma, compiler hints

        // Debug info
        debug_info: bool = true, // Source maps, line numbers

        // Formatting
        whitespace: bool = true, // Preserve formatting style

        // Custom extensions
        custom_syntax: bool = false, // Language extensions
    };

    /// Feature behavior when not supported by target
    pub const FeatureAction = enum {
        error_, // Fail compilation
        warn, // Warn but continue
        transform, // Convert to supported equivalent
        passthrough, // Keep as-is (no runtime effect)
        drop, // Silently remove
    };

    /// Get action for unsupported feature
    pub fn getFeatureAction(self: Capabilities, feature: Feature) FeatureAction {
        return switch (feature) {
            // Always error on critical features
            .threads => if (!self.concurrency.has_threads) .error_ else .passthrough,
            .async_await => if (!self.concurrency.has_async_await) .transform else .passthrough,

            // Transform when possible
            .generics => if (!self.types.has_generics) .transform else .passthrough, // monomorphize
            .option => if (!self.types.has_option) .transform else .passthrough, // to nullable
            .result => if (!self.types.has_result) .transform else .passthrough, // to tuple
            .closures => if (!self.functions.has_closures) .transform else .passthrough, // to fn+env
            .pattern_match => if (!self.control.has_match) .transform else .passthrough, // to if/switch

            // Warn but continue
            .borrow_check => if (!self.memory.has_borrow_checker) .warn else .passthrough,
            .lifetimes => if (!self.memory.has_lifetimes) .warn else .passthrough,

            // Safe to drop
            .type_hints => if (self.passthrough.type_hints) .passthrough else .drop,
            .annotations => if (self.passthrough.annotations) .passthrough else .drop,
            .doc_comments => if (self.passthrough.doc_comments) .passthrough else .drop,
            .comments => if (self.passthrough.comments) .passthrough else .drop,
            .pragmas => if (self.passthrough.pragmas) .passthrough else .drop,

            // Default
            _ => .warn,
        };
    }

    pub const Feature = enum {
        // Types
        generics,
        option,
        result,
        traits,

        // Concurrency
        threads,
        async_await,
        promises,
        channels,

        // Memory
        borrow_check,
        lifetimes,
        manual_memory,

        // Functions
        closures,
        generators,
        tail_calls,

        // Control
        pattern_match,
        exceptions,

        // Passthrough (no runtime effect)
        type_hints,
        annotations,
        doc_comments,
        comments,
        pragmas,
        debug_info,
    };

    pub const TypeSystem = struct {
        // Primitive types
        has_integers: bool = true,
        has_floats: bool = true,
        has_booleans: bool = true,
        has_strings: bool = true,
        has_chars: bool = false,
        has_bytes: bool = false,

        // Compound types
        has_arrays: bool = true,
        has_tuples: bool = false,
        has_structs: bool = false,
        has_enums: bool = false,
        has_unions: bool = false,

        // Advanced types
        has_option: bool = false, // Option<T>, Maybe, ?T
        has_result: bool = false, // Result<T,E>, Either
        has_references: bool = false, // &T
        has_pointers: bool = false, // *T
        has_slices: bool = false, // []T

        // Generics
        has_generics: bool = false,
        has_type_bounds: bool = false, // T: Trait
        has_associated_types: bool = false,

        // OOP
        has_classes: bool = false,
        has_inheritance: bool = false,
        has_interfaces: bool = false, // traits, protocols
        has_mixins: bool = false,

        // Type inference
        has_type_inference: bool = false,
        has_static_typing: bool = false,
        has_dynamic_typing: bool = false,

        // Nullability
        has_null: bool = true,
        has_nullable_types: bool = false, // T?
        null_safety: NullSafety = .none,

        pub const NullSafety = enum {
            none, // null can be anywhere
            optional, // explicit Option/Maybe
            strict, // no null at all
        };
    };

    pub const Concurrency = struct {
        has_threads: bool = false,
        has_async_await: bool = false,
        has_promises: bool = false,
        has_futures: bool = false,
        has_channels: bool = false,
        has_actors: bool = false,
        has_coroutines: bool = false,
        has_green_threads: bool = false,

        // Synchronization
        has_mutexes: bool = false,
        has_atomics: bool = false,
        has_rwlocks: bool = false,
        has_semaphores: bool = false,

        // Memory model
        memory_model: MemoryModel = .none,

        pub const MemoryModel = enum {
            none, // no concurrency guarantees
            sequential, // sequential consistency
            relaxed, // relaxed memory model
            acquire_release, // acquire-release semantics
        };
    };

    pub const Memory = struct {
        has_gc: bool = false,
        has_manual: bool = false, // malloc/free
        has_raii: bool = false, // destructors
        has_arc: bool = false, // reference counting
        has_borrow_checker: bool = false,
        has_lifetimes: bool = false,
        has_move_semantics: bool = false,
        has_copy_semantics: bool = true,

        // Stack vs Heap
        stack_allocation: bool = true,
        heap_allocation: bool = true,
        can_control_allocation: bool = false,
    };

    pub const Functions = struct {
        has_first_class: bool = false, // functions as values
        has_closures: bool = false,
        has_lambdas: bool = false,
        has_higher_order: bool = false,
        has_variadic: bool = false,
        has_default_args: bool = false,
        has_named_args: bool = false,
        has_overloading: bool = false,
        has_operators: bool = false, // operator overloading
        has_recursion: bool = true,
        has_tail_call: bool = false, // TCO guarantee

        // Special
        has_generators: bool = false,
        has_iterators: bool = false,
    };

    pub const ControlFlow = struct {
        has_if_else: bool = true,
        has_switch: bool = false,
        has_match: bool = false, // pattern matching
        has_loops: bool = true,
        has_for_in: bool = false,
        has_while: bool = true,
        has_break: bool = true,
        has_continue: bool = true,
        has_goto: bool = false,
        has_labeled_breaks: bool = false,

        // Exception handling
        has_exceptions: bool = false,
        has_try_catch: bool = false,
        has_panic: bool = false,
        has_result_propagation: bool = false, // ? operator
    };

    pub const Modules = struct {
        has_modules: bool = false,
        has_namespaces: bool = false,
        has_packages: bool = false,
        has_imports: bool = true,
        has_exports: bool = false,
        has_visibility: bool = false, // pub/private
        has_circular_imports: bool = false,
    };

    pub const Metaprogramming = struct {
        has_macros: bool = false,
        has_reflection: bool = false,
        has_comptime: bool = false,
        has_templates: bool = false,
        has_decorators: bool = false,
        has_annotations: bool = false,
        has_code_gen: bool = false,
    };

    pub const Runtime = struct {
        has_runtime: bool = true,
        has_vm: bool = false,
        has_jit: bool = false,
        has_aot: bool = false,
        has_repl: bool = false,
        has_eval: bool = false,
        has_ffi: bool = false,
        has_embedding: bool = false,

        // Platform
        targets_native: bool = false,
        targets_wasm: bool = false,
        targets_js: bool = false,
    };

    // ============ COMPATIBILITY CHECK ============

    /// Check if source can be transpiled to target
    pub fn canTranspileTo(self: Capabilities, target: Capabilities) CompatResult {
        var result = CompatResult{};

        // Check each feature using the action system
        const features_to_check = [_]struct { feature: Feature, source_has: bool, target_has: bool, msg: []const u8 }{
            .{ .feature = .generics, .source_has = self.types.has_generics, .target_has = target.types.has_generics, .msg = "Generics will be monomorphized" },
            .{ .feature = .option, .source_has = self.types.has_option, .target_has = target.types.has_option, .msg = "Option<T> will be lowered to nullable" },
            .{ .feature = .result, .source_has = self.types.has_result, .target_has = target.types.has_result, .msg = "Result<T,E> will be lowered to tuple/error code" },
            .{ .feature = .traits, .source_has = self.types.has_interfaces, .target_has = target.types.has_interfaces, .msg = "Traits will use static dispatch or vtables" },
            .{ .feature = .threads, .source_has = self.concurrency.has_threads, .target_has = target.concurrency.has_threads, .msg = "Threads not supported in target" },
            .{ .feature = .async_await, .source_has = self.concurrency.has_async_await, .target_has = target.concurrency.has_async_await, .msg = "Async/await will be transformed" },
            .{ .feature = .closures, .source_has = self.functions.has_closures, .target_has = target.functions.has_closures, .msg = "Closures will be converted to fn+environment" },
            .{ .feature = .pattern_match, .source_has = self.control.has_match, .target_has = target.control.has_match, .msg = "Pattern matching will use if/switch" },
            .{ .feature = .borrow_check, .source_has = self.memory.has_borrow_checker, .target_has = target.memory.has_borrow_checker, .msg = "Borrow checking not enforced at runtime" },
            .{ .feature = .lifetimes, .source_has = self.memory.has_lifetimes, .target_has = target.memory.has_lifetimes, .msg = "Lifetimes will be erased" },
            .{ .feature = .generators, .source_has = self.functions.has_generators, .target_has = target.functions.has_generators, .msg = "Generators will be transformed to state machines" },
            .{ .feature = .exceptions, .source_has = self.control.has_exceptions, .target_has = target.control.has_exceptions, .msg = "Exceptions will use error codes" },
        };

        for (features_to_check) |check| {
            if (check.source_has and !check.target_has) {
                const action = target.getFeatureAction(check.feature);
                switch (action) {
                    .error_ => result.addError(check.msg),
                    .warn => result.addWarning(check.msg),
                    .transform => result.addInfo(check.msg),
                    .passthrough, .drop => {}, // Silent
                }
            }
        }

        return result;
    }

    /// Check if a specific feature needs transformation
    pub fn needsTransform(self: Capabilities, target: Capabilities, feature: Feature) bool {
        const action = target.getFeatureAction(feature);
        return action == .transform;
    }

    /// Check if a feature can be passed through unchanged
    pub fn canPassthrough(self: Capabilities, feature: Feature) bool {
        const action = self.getFeatureAction(feature);
        return action == .passthrough;
    }
};

pub const CompatResult = struct {
    errors: std.BoundedArray([]const u8, 32) = .{},
    warnings: std.BoundedArray([]const u8, 32) = .{},
    info: std.BoundedArray([]const u8, 32) = .{}, // Transforms that will happen

    pub fn addError(self: *CompatResult, msg: []const u8) void {
        self.errors.append(msg) catch {};
    }

    pub fn addWarning(self: *CompatResult, msg: []const u8) void {
        self.warnings.append(msg) catch {};
    }

    pub fn addInfo(self: *CompatResult, msg: []const u8) void {
        self.info.append(msg) catch {};
    }

    pub fn isCompatible(self: CompatResult) bool {
        return self.errors.len == 0;
    }

    pub fn hasWarnings(self: CompatResult) bool {
        return self.warnings.len > 0;
    }

    pub fn hasTransforms(self: CompatResult) bool {
        return self.info.len > 0;
    }
};

// ============ PREDEFINED LANGUAGE CAPABILITIES ============

pub const lua = Capabilities{
    .name = "lua",
    .version = "5.4",
    .types = .{
        .has_integers = true,
        .has_floats = true,
        .has_booleans = true,
        .has_strings = true,
        .has_arrays = true, // tables
        .has_tuples = false,
        .has_structs = false, // tables as structs
        .has_dynamic_typing = true,
        .has_null = true, // nil
    },
    .concurrency = .{
        .has_coroutines = true,
    },
    .memory = .{
        .has_gc = true,
    },
    .functions = .{
        .has_first_class = true,
        .has_closures = true,
        .has_variadic = true,
        .has_higher_order = true,
        .has_tail_call = true,
    },
    .control = .{
        .has_if_else = true,
        .has_loops = true,
        .has_for_in = true,
        .has_while = true,
        .has_break = true,
    },
    .modules = .{
        .has_modules = true, // require
        .has_imports = true,
    },
    .meta = .{
        .has_reflection = true, // metatables
        .has_eval = true, // loadstring
    },
    .runtime = .{
        .has_runtime = true,
        .has_vm = true,
        .has_repl = true,
        .has_eval = true,
        .has_ffi = true, // LuaJIT FFI
        .has_embedding = true,
    },
};

pub const rust = Capabilities{
    .name = "rust",
    .version = "1.75",
    .types = .{
        .has_integers = true,
        .has_floats = true,
        .has_booleans = true,
        .has_strings = true,
        .has_chars = true,
        .has_bytes = true,
        .has_arrays = true,
        .has_tuples = true,
        .has_structs = true,
        .has_enums = true,
        .has_unions = true,
        .has_option = true,
        .has_result = true,
        .has_references = true,
        .has_pointers = true,
        .has_slices = true,
        .has_generics = true,
        .has_type_bounds = true,
        .has_associated_types = true,
        .has_interfaces = true, // traits
        .has_type_inference = true,
        .has_static_typing = true,
        .has_null = false,
        .null_safety = .strict,
    },
    .concurrency = .{
        .has_threads = true,
        .has_async_await = true,
        .has_futures = true,
        .has_channels = true,
        .has_mutexes = true,
        .has_atomics = true,
        .has_rwlocks = true,
        .memory_model = .acquire_release,
    },
    .memory = .{
        .has_manual = true,
        .has_raii = true,
        .has_borrow_checker = true,
        .has_lifetimes = true,
        .has_move_semantics = true,
        .can_control_allocation = true,
    },
    .functions = .{
        .has_first_class = true,
        .has_closures = true,
        .has_lambdas = true,
        .has_higher_order = true,
        .has_default_args = false,
        .has_named_args = false,
        .has_operators = true,
        .has_iterators = true,
    },
    .control = .{
        .has_if_else = true,
        .has_match = true,
        .has_loops = true,
        .has_for_in = true,
        .has_while = true,
        .has_break = true,
        .has_continue = true,
        .has_labeled_breaks = true,
        .has_panic = true,
        .has_result_propagation = true,
    },
    .modules = .{
        .has_modules = true,
        .has_packages = true, // crates
        .has_imports = true, // use
        .has_exports = true,
        .has_visibility = true,
    },
    .meta = .{
        .has_macros = true,
        .has_comptime = true, // const fn
        .has_decorators = true, // derive, attributes
        .has_code_gen = true, // proc macros
    },
    .runtime = .{
        .has_runtime = false, // no GC runtime
        .has_aot = true,
        .has_ffi = true,
        .targets_native = true,
        .targets_wasm = true,
    },
};

pub const wat = Capabilities{
    .name = "wat",
    .version = "2.0",
    .types = .{
        .has_integers = true, // i32, i64
        .has_floats = true, // f32, f64
        .has_booleans = false, // represented as i32
        .has_strings = false, // memory + data
        .has_arrays = false, // memory
        .has_static_typing = true,
        .has_null = false,
    },
    .concurrency = .{
        .has_threads = true, // threads proposal
        .has_atomics = true, // atomics proposal
    },
    .memory = .{
        .has_manual = true, // linear memory
        .stack_allocation = true,
        .heap_allocation = true,
        .can_control_allocation = true,
    },
    .functions = .{
        .has_first_class = true, // funcref
        .has_recursion = true,
        .has_tail_call = true, // tail call proposal
    },
    .control = .{
        .has_if_else = true,
        .has_loops = true,
        .has_break = true, // br
        .has_labeled_breaks = true, // br $label
    },
    .modules = .{
        .has_modules = true,
        .has_imports = true,
        .has_exports = true,
    },
    .runtime = .{
        .has_runtime = true, // wasm runtime
        .has_vm = true,
        .has_jit = true, // browser JIT
        .has_aot = true, // wasmtime AOT
        .targets_wasm = true,
    },
};

pub const javascript = Capabilities{
    .name = "javascript",
    .version = "ES2023",
    .types = .{
        .has_integers = false, // all numbers are f64
        .has_floats = true,
        .has_booleans = true,
        .has_strings = true,
        .has_arrays = true,
        .has_structs = true, // objects
        .has_classes = true,
        .has_inheritance = true, // prototype
        .has_dynamic_typing = true,
        .has_null = true,
    },
    .concurrency = .{
        .has_async_await = true,
        .has_promises = true,
        .has_green_threads = true, // event loop
    },
    .memory = .{
        .has_gc = true,
    },
    .functions = .{
        .has_first_class = true,
        .has_closures = true,
        .has_lambdas = true, // arrow functions
        .has_higher_order = true,
        .has_variadic = true,
        .has_default_args = true,
        .has_generators = true,
        .has_iterators = true,
    },
    .control = .{
        .has_if_else = true,
        .has_switch = true,
        .has_loops = true,
        .has_for_in = true,
        .has_while = true,
        .has_break = true,
        .has_continue = true,
        .has_exceptions = true,
        .has_try_catch = true,
    },
    .modules = .{
        .has_modules = true, // ESM
        .has_imports = true,
        .has_exports = true,
    },
    .meta = .{
        .has_reflection = true,
        .has_decorators = true,
        .has_eval = true,
    },
    .runtime = .{
        .has_runtime = true,
        .has_vm = true,
        .has_jit = true,
        .has_repl = true,
        .has_eval = true,
        .targets_js = true,
        .targets_wasm = true, // via wasm-bindgen
    },
};

pub const c = Capabilities{
    .name = "c",
    .version = "C17",
    .types = .{
        .has_integers = true,
        .has_floats = true,
        .has_booleans = true, // stdbool.h
        .has_strings = false, // char*
        .has_chars = true,
        .has_bytes = true,
        .has_arrays = true,
        .has_structs = true,
        .has_enums = true,
        .has_unions = true,
        .has_pointers = true,
        .has_static_typing = true,
        .has_null = true, // NULL
    },
    .concurrency = .{
        .has_threads = true, // pthreads
        .has_mutexes = true,
        .has_atomics = true, // C11
    },
    .memory = .{
        .has_manual = true,
        .stack_allocation = true,
        .heap_allocation = true,
        .can_control_allocation = true,
    },
    .functions = .{
        .has_variadic = true,
        .has_recursion = true,
    },
    .control = .{
        .has_if_else = true,
        .has_switch = true,
        .has_loops = true,
        .has_while = true,
        .has_break = true,
        .has_continue = true,
        .has_goto = true,
    },
    .modules = .{
        .has_imports = true, // #include
    },
    .meta = .{
        .has_macros = true, // preprocessor
    },
    .runtime = .{
        .has_aot = true,
        .has_ffi = true,
        .targets_native = true,
    },
};

pub const python = Capabilities{
    .name = "python",
    .version = "3.12",
    .types = .{
        .has_integers = true,
        .has_floats = true,
        .has_booleans = true,
        .has_strings = true,
        .has_arrays = true, // lists
        .has_tuples = true,
        .has_structs = true, // dataclasses
        .has_enums = true,
        .has_classes = true,
        .has_inheritance = true,
        .has_interfaces = true, // ABC, Protocol
        .has_generics = true, // typing
        .has_type_inference = true,
        .has_dynamic_typing = true,
        .has_null = true, // None
    },
    .concurrency = .{
        .has_threads = true,
        .has_async_await = true,
        .has_coroutines = true,
        .has_green_threads = true, // asyncio
    },
    .memory = .{
        .has_gc = true,
        .has_arc = true, // refcounting
    },
    .functions = .{
        .has_first_class = true,
        .has_closures = true,
        .has_lambdas = true,
        .has_higher_order = true,
        .has_variadic = true,
        .has_default_args = true,
        .has_named_args = true,
        .has_operators = true,
        .has_generators = true,
        .has_iterators = true,
    },
    .control = .{
        .has_if_else = true,
        .has_match = true, // 3.10+
        .has_loops = true,
        .has_for_in = true,
        .has_while = true,
        .has_break = true,
        .has_continue = true,
        .has_exceptions = true,
        .has_try_catch = true,
    },
    .modules = .{
        .has_modules = true,
        .has_packages = true,
        .has_imports = true,
        .has_exports = true, // __all__
    },
    .meta = .{
        .has_reflection = true,
        .has_decorators = true,
        .has_annotations = true,
    },
    .runtime = .{
        .has_runtime = true,
        .has_vm = true,
        .has_repl = true,
        .has_eval = true,
        .has_ffi = true, // ctypes
    },
};

// ============ CAPABILITY LOOKUP ============

pub fn get(lang: []const u8) ?Capabilities {
    const map = std.StaticStringMap(Capabilities).initComptime(.{
        .{ "lua", lua },
        .{ "rust", rust },
        .{ "wat", wat },
        .{ "wasm", wat },
        .{ "javascript", javascript },
        .{ "js", javascript },
        .{ "c", c },
        .{ "python", python },
        .{ "py", python },
    });
    return map.get(lang);
}

// ============ TESTS ============

test "lua to wat compatibility" {
    const result = lua.canTranspileTo(wat);
    try std.testing.expect(result.isCompatible());
    try std.testing.expect(result.hasWarnings()); // closures warning
}

test "rust to wat compatibility" {
    const result = rust.canTranspileTo(wat);
    try std.testing.expect(result.hasWarnings()); // generics, option, result
}
