const std = @import("std");
const capabilities = @import("capabilities.zig");

/// LLM-Assisted Transpilation
/// For features that can't be automatically transpiled, we mark them
/// and send to an LLM for intelligent conversion
pub const LLMTranspiler = struct {
    alloc: std.mem.Allocator,
    conflicts: std.ArrayList(Conflict),
    responses: std.ArrayList(LLMResponse),
    config: Config,

    pub const Config = struct {
        /// LLM endpoint URL
        endpoint: []const u8 = "http://localhost:11434/api/generate",

        /// Model to use
        model: []const u8 = "codellama",

        /// Max tokens for response
        max_tokens: u32 = 2048,

        /// Temperature (0 = deterministic, 1 = creative)
        temperature: f32 = 0.2,

        /// Custom system prompt
        system_prompt: ?[]const u8 = null,

        /// Timeout in milliseconds
        timeout_ms: u32 = 30000,

        /// Dry run mode (don't call LLM, just collect conflicts)
        dry_run: bool = false,
    };

    /// A conflict that needs LLM assistance
    pub const Conflict = struct {
        /// Type of conflict
        kind: Kind,

        /// Source code snippet
        source: []const u8,

        /// Location in source
        location: Location,

        /// Source language
        source_lang: []const u8,

        /// Target language
        target_lang: []const u8,

        /// Feature that caused the conflict
        feature: capabilities.Capabilities.Feature,

        /// Additional context
        context: ?[]const u8 = null,

        /// Suggested transformation (if any)
        suggestion: ?[]const u8 = null,

        pub const Kind = enum {
            unsupported_feature, // Feature doesn't exist in target
            semantic_mismatch, // Behavior differs between languages
            type_incompatible, // Type system mismatch
            runtime_dependent, // Needs runtime info to transpile
            ambiguous, // Multiple valid translations
            complex_pattern, // Pattern too complex for rules
        };

        pub const Location = struct {
            line: u32,
            column: u32,
            end_line: u32 = 0,
            end_column: u32 = 0,
            file: ?[]const u8 = null,
        };
    };

    /// Response from LLM
    pub const LLMResponse = struct {
        /// The transpiled code
        code: []const u8,

        /// Warnings emitted by LLM
        warnings: []const Warning,

        /// Confidence level (0-1)
        confidence: f32,

        /// Explanation of the transformation
        explanation: ?[]const u8 = null,

        /// Alternative translations
        alternatives: []const Alternative = &.{},

        pub const Warning = struct {
            level: Level,
            message: []const u8,
            suggestion: ?[]const u8 = null,

            pub const Level = enum {
                info, // Informational
                warning, // Potential issue
                critical, // Likely incorrect
            };
        };

        pub const Alternative = struct {
            code: []const u8,
            description: []const u8,
            tradeoffs: []const u8,
        };
    };

    pub fn init(alloc: std.mem.Allocator, config: Config) LLMTranspiler {
        return .{
            .alloc = alloc,
            .conflicts = std.ArrayList(Conflict).init(alloc),
            .responses = std.ArrayList(LLMResponse).init(alloc),
            .config = config,
        };
    }

    pub fn deinit(self: *LLMTranspiler) void {
        self.conflicts.deinit();
        self.responses.deinit();
    }

    /// Add a conflict that needs LLM assistance
    pub fn addConflict(self: *LLMTranspiler, conflict: Conflict) !void {
        try self.conflicts.append(conflict);
    }

    /// Mark a code region as needing LLM assistance
    pub fn markForLLM(
        self: *LLMTranspiler,
        source: []const u8,
        source_lang: []const u8,
        target_lang: []const u8,
        feature: capabilities.Capabilities.Feature,
        line: u32,
        column: u32,
    ) !void {
        try self.addConflict(.{
            .kind = .unsupported_feature,
            .source = source,
            .location = .{ .line = line, .column = column },
            .source_lang = source_lang,
            .target_lang = target_lang,
            .feature = feature,
        });
    }

    /// Process all conflicts with LLM
    pub fn processConflicts(self: *LLMTranspiler) !void {
        if (self.config.dry_run) {
            return; // Just collect, don't call LLM
        }

        for (self.conflicts.items) |conflict| {
            const response = try self.callLLM(conflict);
            try self.responses.append(response);
        }
    }

    /// Call LLM for a single conflict
    fn callLLM(self: *LLMTranspiler, conflict: Conflict) !LLMResponse {
        const prompt = try self.buildPrompt(conflict);
        defer self.alloc.free(prompt);

        // Build request body
        var request_body = std.ArrayList(u8).init(self.alloc);
        defer request_body.deinit();

        try std.json.stringify(.{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .options = .{
                .temperature = self.config.temperature,
                .num_predict = self.config.max_tokens,
            },
        }, .{}, request_body.writer());

        // Make HTTP request (simplified - real impl would use http client)
        // For now, return a placeholder that the actual HTTP call would populate
        return self.parseResponse("", conflict);
    }

    /// Build prompt for LLM
    fn buildPrompt(self: *LLMTranspiler, conflict: Conflict) ![]const u8 {
        var prompt = std.ArrayList(u8).init(self.alloc);
        const w = prompt.writer();

        // System context
        const system = self.config.system_prompt orelse
            \\You are an expert code transpiler. Convert code between programming languages
            \\while preserving semantics. Emit warnings for potential issues.
            \\
            \\Response format:
            \\```<target_lang>
            \\<transpiled code>
            \\```
            \\
            \\WARNINGS:
            \\- [level] message
            \\
            \\CONFIDENCE: 0.0-1.0
            \\
            \\EXPLANATION: <why this translation is correct>
        ;

        try w.print("{s}\n\n", .{system});

        // Task
        try w.print("Transpile this {s} code to {s}:\n\n", .{ conflict.source_lang, conflict.target_lang });

        // Source code
        try w.print("```{s}\n{s}\n```\n\n", .{ conflict.source_lang, conflict.source });

        // Context about the conflict
        try w.print("ISSUE: {s}\n", .{@tagName(conflict.kind)});
        try w.print("FEATURE: {s}\n", .{@tagName(conflict.feature)});

        if (conflict.context) |ctx| {
            try w.print("CONTEXT: {s}\n", .{ctx});
        }

        if (conflict.suggestion) |sug| {
            try w.print("SUGGESTION: {s}\n", .{sug});
        }

        // Target language capabilities
        if (capabilities.get(conflict.target_lang)) |caps| {
            try w.print("\nTARGET CAPABILITIES:\n", .{});
            try w.print("- has_generics: {}\n", .{caps.types.has_generics});
            try w.print("- has_async: {}\n", .{caps.concurrency.has_async_await});
            try w.print("- has_closures: {}\n", .{caps.functions.has_closures});
            try w.print("- has_exceptions: {}\n", .{caps.control.has_exceptions});
        }

        return prompt.toOwnedSlice();
    }

    /// Parse LLM response
    fn parseResponse(self: *LLMTranspiler, raw: []const u8, conflict: Conflict) !LLMResponse {
        _ = conflict;
        _ = raw;

        // TODO: Parse actual LLM response
        // For now, return empty response
        return LLMResponse{
            .code = "",
            .warnings = &.{},
            .confidence = 0.0,
        };
    }

    /// Get all warnings from LLM responses
    pub fn getWarnings(self: *LLMTranspiler) []const LLMResponse.Warning {
        var warnings = std.ArrayList(LLMResponse.Warning).init(self.alloc);
        for (self.responses.items) |response| {
            warnings.appendSlice(response.warnings) catch {};
        }
        return warnings.items;
    }

    /// Get transpiled code for a conflict by index
    pub fn getTranspiled(self: *LLMTranspiler, index: usize) ?[]const u8 {
        if (index >= self.responses.items.len) return null;
        return self.responses.items[index].code;
    }

    /// Check if all conflicts were resolved with high confidence
    pub fn allResolved(self: *LLMTranspiler, min_confidence: f32) bool {
        for (self.responses.items) |response| {
            if (response.confidence < min_confidence) return false;
        }
        return true;
    }

    /// Export conflicts for manual review or batch processing
    pub fn exportConflicts(self: *LLMTranspiler) ![]const u8 {
        var out = std.ArrayList(u8).init(self.alloc);
        const w = out.writer();

        try w.print("# Transpilation Conflicts\n\n", .{});
        try w.print("Total: {d} conflicts\n\n", .{self.conflicts.items.len});

        for (self.conflicts.items, 0..) |conflict, i| {
            try w.print("## Conflict {d}\n\n", .{i + 1});
            try w.print("- **Kind**: {s}\n", .{@tagName(conflict.kind)});
            try w.print("- **Feature**: {s}\n", .{@tagName(conflict.feature)});
            try w.print("- **From**: {s} → {s}\n", .{ conflict.source_lang, conflict.target_lang });
            try w.print("- **Location**: line {d}, col {d}\n\n", .{ conflict.location.line, conflict.location.column });
            try w.print("```{s}\n{s}\n```\n\n", .{ conflict.source_lang, conflict.source });

            if (conflict.context) |ctx| {
                try w.print("**Context**: {s}\n\n", .{ctx});
            }
        }

        return out.toOwnedSlice();
    }
};

/// Integration with IR pipeline
pub const LLMPipelineIntegration = struct {
    /// Check IR node for conflicts and mark for LLM
    pub fn checkNode(
        transpiler: *LLMTranspiler,
        node: anytype,
        source_lang: []const u8,
        target_lang: []const u8,
        target_caps: capabilities.Capabilities,
    ) !void {
        // Check for features that need LLM assistance
        const features_to_check = [_]struct {
            feature: capabilities.Capabilities.Feature,
            needs_llm: bool,
        }{
            .{ .feature = .generics, .needs_llm = !target_caps.types.has_generics },
            .{ .feature = .async_await, .needs_llm = !target_caps.concurrency.has_async_await },
            .{ .feature = .pattern_match, .needs_llm = !target_caps.control.has_match },
            .{ .feature = .closures, .needs_llm = !target_caps.functions.has_closures },
            .{ .feature = .generators, .needs_llm = !target_caps.functions.has_generators },
        };

        for (features_to_check) |check| {
            if (check.needs_llm and nodeUsesFeature(node, check.feature)) {
                const action = target_caps.getFeatureAction(check.feature);
                if (action == .transform) {
                    // Complex transform - use LLM
                    try transpiler.markForLLM(
                        nodeToSource(node),
                        source_lang,
                        target_lang,
                        check.feature,
                        nodeGetLine(node),
                        nodeGetColumn(node),
                    );
                }
            }
        }
    }

    fn nodeUsesFeature(node: anytype, feature: capabilities.Capabilities.Feature) bool {
        _ = node;
        _ = feature;
        // TODO: Implement feature detection from IR nodes
        return false;
    }

    fn nodeToSource(node: anytype) []const u8 {
        _ = node;
        return "";
    }

    fn nodeGetLine(node: anytype) u32 {
        _ = node;
        return 0;
    }

    fn nodeGetColumn(node: anytype) u32 {
        _ = node;
        return 0;
    }
};

// ============ TESTS ============

test "create conflict" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var transpiler = LLMTranspiler.init(arena.allocator(), .{ .dry_run = true });
    defer transpiler.deinit();

    try transpiler.markForLLM(
        "async fn fetch() { await http.get() }",
        "rust",
        "wat",
        .async_await,
        10,
        5,
    );

    try std.testing.expectEqual(@as(usize, 1), transpiler.conflicts.items.len);
}

test "build prompt" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var transpiler = LLMTranspiler.init(arena.allocator(), .{});

    const conflict = LLMTranspiler.Conflict{
        .kind = .unsupported_feature,
        .source = "match x { Some(v) => v, None => 0 }",
        .location = .{ .line = 1, .column = 1 },
        .source_lang = "rust",
        .target_lang = "lua",
        .feature = .pattern_match,
    };

    const prompt = try transpiler.buildPrompt(conflict);
    defer arena.allocator().free(prompt);

    try std.testing.expect(std.mem.indexOf(u8, prompt, "rust") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "lua") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "pattern_match") != null);
}
