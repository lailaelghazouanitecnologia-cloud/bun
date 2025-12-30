//! Progress - Progress tracking and display
//!
//! Pattern from Bun's Progress.zig.
//! Provides thread-safe, non-allocating progress indicators.
//! Nodes form a tree of nested progress items.

const std = @import("std");
const builtin = @import("builtin");
const Environment = @import("../env.zig");
const Output = @import("../output.zig");

const Progress = @This();

/// Terminal output target
terminal: ?std.fs.File = undefined,

/// Whether terminal supports ANSI
supports_ansi: bool = false,

/// Root progress node
root: Node = undefined,

/// Timer for refresh rate limiting
timer: ?std.time.Timer = null,

/// Previous refresh timestamp
prev_refresh: u64 = 0,

/// Output buffer
output_buffer: [256]u8 = undefined,

/// Nanoseconds between refreshes (default 50ms)
refresh_rate_ns: u64 = 50 * std.time.ns_per_ms,

/// Initial delay before showing progress (default 500ms)
initial_delay_ns: u64 = 500 * std.time.ns_per_ms,

/// Whether progress is done
done: bool = true,

/// Mutex for thread-safe updates
mutex: std.Thread.Mutex = .{},

/// Columns written (for cursor restore)
columns_written: usize = 0,

// ============ NODE ============

/// A single progress node (can have children)
pub const Node = struct {
    context: *Progress,
    parent: ?*Node,
    name: []const u8,
    unit: Unit = .none,

    /// Child node (atomic for thread safety)
    child: ?*Node = null,

    /// Total items expected (0 = unknown)
    total: usize = 0,

    /// Items completed
    completed: usize = 0,

    pub const Unit = enum {
        none,
        files,
        bytes,
        percent,
    };

    /// Create child node
    pub fn start(self: *Node, name: []const u8, total: usize) Node {
        return Node{
            .context = self.context,
            .parent = self,
            .name = name,
            .total = total,
        };
    }

    /// Complete one item and update
    pub fn completeOne(self: *Node) void {
        if (self.parent) |parent| {
            @atomicStore(?*Node, &parent.child, self, .release);
        }
        _ = @atomicRmw(usize, &self.completed, .Add, 1, .monotonic);
        self.context.maybeRefresh();
    }

    /// Complete multiple items
    pub fn complete(self: *Node, count: usize) void {
        if (self.parent) |parent| {
            @atomicStore(?*Node, &parent.child, self, .release);
        }
        _ = @atomicRmw(usize, &self.completed, .Add, count, .monotonic);
        self.context.maybeRefresh();
    }

    /// Finish this node
    pub fn end(self: *Node) void {
        self.context.maybeRefresh();
        if (self.parent) |parent| {
            self.context.mutex.lock();
            defer self.context.mutex.unlock();
            _ = @cmpxchgStrong(?*Node, &parent.child, self, null, .monotonic, .monotonic);
            parent.completeOne();
        } else {
            self.context.mutex.lock();
            defer self.context.mutex.unlock();
            self.context.done = true;
            self.context.refreshLocked();
        }
    }

    /// Activate this node (show in parent)
    pub fn activate(self: *Node) void {
        if (self.parent) |parent| {
            @atomicStore(?*Node, &parent.child, self, .release);
            self.context.maybeRefresh();
        }
    }

    /// Set node name
    pub fn setName(self: *Node, name: []const u8) void {
        self.context.mutex.lock();
        defer self.context.mutex.unlock();
        self.name = name;
        if (self.parent) |parent| {
            @atomicStore(?*Node, &parent.child, self, .release);
        }
    }

    /// Set total items
    pub fn setTotal(self: *Node, total: usize) void {
        @atomicStore(usize, &self.total, total, .monotonic);
    }

    /// Set completed items
    pub fn setCompleted(self: *Node, completed: usize) void {
        @atomicStore(usize, &self.completed, completed, .monotonic);
    }

    /// Get progress as percentage (0-100)
    pub fn percent(self: *const Node) u8 {
        const t = @atomicLoad(usize, &self.total, .monotonic);
        if (t == 0) return 0;
        const c = @atomicLoad(usize, &self.completed, .monotonic);
        return @intCast(@min(100, (c * 100) / t));
    }
};

// ============ PROGRESS CONTROL ============

/// Start progress tracking
pub fn start(self: *Progress, name: []const u8, total: usize) *Node {
    const stderr = std.io.getStdErr();
    self.terminal = null;

    if (stderr.supportsAnsiEscapeCodes()) {
        self.terminal = stderr;
        self.supports_ansi = true;
    } else if (builtin.os.tag != .windows) {
        self.terminal = stderr;
    }

    self.root = Node{
        .context = self,
        .parent = null,
        .name = name,
        .total = total,
    };

    self.columns_written = 0;
    self.prev_refresh = 0;
    self.timer = std.time.Timer.start() catch null;
    self.done = false;

    return &self.root;
}

/// Maybe refresh (rate-limited)
pub fn maybeRefresh(self: *Progress) void {
    if (self.timer) |*timer| {
        if (!self.mutex.tryLock()) return;
        defer self.mutex.unlock();

        const now = timer.read();
        if (now < self.initial_delay_ns) return;
        if (now < self.prev_refresh) return;
        if (now - self.prev_refresh < self.refresh_rate_ns) return;

        self.refreshLocked();
    }
}

/// Force refresh
pub fn refresh(self: *Progress) void {
    if (!self.mutex.tryLock()) return;
    defer self.mutex.unlock();
    self.refreshLocked();
}

fn refreshLocked(self: *Progress) void {
    const file = self.terminal orelse return;

    var end: usize = 0;

    // Clear previous output
    if (self.columns_written > 0) {
        if (self.supports_ansi) {
            end += (std.fmt.bufPrint(self.output_buffer[end..], "\x1b[{d}D\x1b[0K", .{self.columns_written}) catch return).len;
        } else {
            self.output_buffer[end] = '\n';
            end += 1;
        }
        self.columns_written = 0;
    }

    if (!self.done) {
        // Walk the node tree
        var maybe_node: ?*Node = &self.root;
        var need_sep = false;

        while (maybe_node) |node| {
            if (need_sep) {
                end += (std.fmt.bufPrint(self.output_buffer[end..], " > ", .{}) catch break).len;
            }
            need_sep = false;

            const total = @atomicLoad(usize, &node.total, .monotonic);
            const completed = @atomicLoad(usize, &node.completed, .monotonic);
            const current = completed + 1;

            if (node.name.len != 0) {
                end += (std.fmt.bufPrint(self.output_buffer[end..], "{s}", .{node.name}) catch break).len;
                need_sep = true;
            }

            if (total > 0) {
                if (need_sep) {
                    end += (std.fmt.bufPrint(self.output_buffer[end..], " ", .{}) catch break).len;
                }
                end += (std.fmt.bufPrint(self.output_buffer[end..], "[{d}/{d}]", .{ current, total }) catch break).len;
                need_sep = true;
            } else if (completed != 0) {
                if (need_sep) {
                    end += (std.fmt.bufPrint(self.output_buffer[end..], " ", .{}) catch break).len;
                }
                end += (std.fmt.bufPrint(self.output_buffer[end..], "[{d}]", .{current}) catch break).len;
                need_sep = true;
            }

            maybe_node = @atomicLoad(?*Node, &node.child, .acquire);
        }
    }

    if (end > 0) {
        file.writeAll(self.output_buffer[0..end]) catch {};
        self.columns_written = end;
    }

    if (self.timer) |*timer| {
        self.prev_refresh = timer.read();
    }
}

// ============ SIMPLE PROGRESS BAR ============

/// Simple progress bar (standalone, no hierarchy)
pub const Bar = struct {
    total: usize,
    current: usize = 0,
    width: u8 = 40,
    label: []const u8 = "",
    show_percent: bool = true,
    show_count: bool = true,

    pub fn init(total: usize) Bar {
        return Bar{ .total = total };
    }

    pub fn update(self: *Bar, current: usize) void {
        self.current = current;
        self.render();
    }

    pub fn increment(self: *Bar) void {
        self.current += 1;
        self.render();
    }

    pub fn finish(self: *Bar) void {
        self.current = self.total;
        self.render();
        Output.print("\n", .{});
    }

    pub fn render(self: *const Bar) void {
        const percent: u8 = if (self.total == 0) 100 else @intCast(@min(100, (self.current * 100) / self.total));
        const filled = (percent * self.width) / 100;

        // Build bar
        var bar_buf: [64]u8 = undefined;
        var i: usize = 0;

        bar_buf[i] = '[';
        i += 1;

        for (0..filled) |_| {
            bar_buf[i] = '=';
            i += 1;
        }

        if (filled < self.width) {
            bar_buf[i] = '>';
            i += 1;
            for (filled + 1..self.width) |_| {
                bar_buf[i] = ' ';
                i += 1;
            }
        }

        bar_buf[i] = ']';
        i += 1;

        // Carriage return and print
        Output.print("\r", .{});
        if (self.label.len > 0) {
            Output.print("{s} ", .{self.label});
        }
        Output.print("{s}", .{bar_buf[0..i]});

        if (self.show_percent) {
            Output.print(" {d:>3}%", .{percent});
        }
        if (self.show_count) {
            Output.print(" ({d}/{d})", .{ self.current, self.total });
        }
    }
};

// ============ SPINNER ============

/// Animated spinner for indeterminate progress
pub const Spinner = struct {
    frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    frame: usize = 0,
    message: []const u8 = "",
    active: bool = false,

    const Self = @This();

    pub fn start(self: *Self, message: []const u8) void {
        self.message = message;
        self.active = true;
        self.render();
    }

    pub fn tick(self: *Self) void {
        if (!self.active) return;
        self.frame = (self.frame + 1) % self.frames.len;
        self.render();
    }

    pub fn stop(self: *Self, final_message: ?[]const u8) void {
        self.active = false;
        Output.print("\r\x1b[K", .{}); // Clear line
        if (final_message) |msg| {
            Output.print("{s}\n", .{msg});
        }
    }

    fn render(self: *const Self) void {
        Output.print("\r{s} {s}", .{ self.frames[self.frame], self.message });
    }
};

// ============ TASK TRACKER ============

/// Track multiple named tasks
pub const TaskTracker = struct {
    tasks: [MAX_TASKS]Task = undefined,
    count: usize = 0,
    start_time: i64 = 0,

    const MAX_TASKS = 32;

    pub const Task = struct {
        name: []const u8,
        status: Status = .pending,
        start_time: i64 = 0,
        end_time: i64 = 0,

        pub const Status = enum {
            pending,
            running,
            done,
            failed,
            skipped,
        };

        pub fn duration(self: *const Task) i64 {
            if (self.end_time == 0) return 0;
            return self.end_time - self.start_time;
        }
    };

    pub fn init() TaskTracker {
        return TaskTracker{
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn add(self: *TaskTracker, name: []const u8) ?*Task {
        if (self.count >= MAX_TASKS) return null;
        self.tasks[self.count] = Task{
            .name = name,
            .start_time = std.time.milliTimestamp(),
        };
        self.count += 1;
        return &self.tasks[self.count - 1];
    }

    pub fn startTask(self: *TaskTracker, name: []const u8) ?*Task {
        if (self.add(name)) |task| {
            task.status = .running;
            return task;
        }
        return null;
    }

    pub fn finishTask(task: *Task, status: Task.Status) void {
        task.status = status;
        task.end_time = std.time.milliTimestamp();
    }

    pub fn summary(self: *const TaskTracker) void {
        var done_count: usize = 0;
        var failed_count: usize = 0;
        var total_duration: i64 = 0;

        for (self.tasks[0..self.count]) |*task| {
            switch (task.status) {
                .done => done_count += 1,
                .failed => failed_count += 1,
                else => {},
            }
            total_duration += task.duration();
        }

        const wall_time = std.time.milliTimestamp() - self.start_time;

        Output.print("\n{d} tasks completed", .{done_count});
        if (failed_count > 0) {
            Output.print(", {d} failed", .{failed_count});
        }
        Output.print(" in {d}ms\n", .{wall_time});
    }
};

// ============ TESTS ============

test "Bar basic" {
    var bar = Bar.init(100);
    bar.label = "Test";
    bar.update(50);
    try std.testing.expectEqual(@as(usize, 50), bar.current);
}

test "Node percent" {
    var progress = Progress{};
    const node = progress.start("test", 100);
    node.setCompleted(50);
    try std.testing.expectEqual(@as(u8, 50), node.percent());
}

test "TaskTracker" {
    var tracker = TaskTracker.init();
    const task = tracker.add("test task");
    try std.testing.expect(task != null);
    try std.testing.expectEqual(@as(usize, 1), tracker.count);
}
