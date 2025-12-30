//! HTTP Module
//!
//! HTTP client for downloading toolchains and making API requests.

pub const Client = @import("client.zig").Client;
pub const Response = @import("client.zig").Response;
pub const Method = @import("client.zig").Method;
pub const Header = @import("client.zig").Header;
pub const Progress = @import("client.zig").Progress;
pub const RequestOptions = @import("client.zig").RequestOptions;
pub const DownloadOptions = @import("client.zig").DownloadOptions;
pub const Url = @import("client.zig").Url;

// Convenience functions
pub const get = @import("client.zig").get;
pub const download = @import("client.zig").download;
