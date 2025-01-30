pub const @"build.Backend" = enum (u1) {
    ncurses = 0,
    crossterm = 1,
};
pub const backend: @"build.Backend" = .crossterm;
