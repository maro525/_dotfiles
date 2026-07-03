local wezterm = require 'wezterm'

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

config.automatically_reload_config = true

config.default_domain = 'WSL:Ubuntu'
config.use_ime = true
config.color_scheme = 'Materia (base16)'
config.window_close_confirmation = 'AlwaysPrompt'
config.enable_scroll_bar = true
config.initial_rows = 60
config.initial_cols = 100
config.default_cursor_style = 'BlinkingUnderline'
config.window_background_opacity = 0.95
config.macos_window_background_blur = 20
config.window_decorations = "RESIZE"

config.font = wezterm.font(
 "Moralerspace Argon HWJPDOC",
 { 
   stretch = 'Normal',
   weight = 'Regular',
   bold = false,
   italic = false,
  }
)
config.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }
config.text_background_opacity = 0.95
config.font_size = 9
config.cell_width = 1.1
config.line_height = 1.1
config.use_cap_height_to_scale_fallback_fonts = true

-- This increases color saturation by 50%
config.foreground_text_hsb = {
 hue = 1.0,
 saturation = 1.0,
 brightness = 1.2,
}

return config
