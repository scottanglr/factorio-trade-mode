local trade_box = table.deepcopy(data.raw.container["steel-chest"])
local accent_tint = {r = 0.74, g = 0.96, b = 0.58, a = 1}

trade_box.name = "trade-box"
trade_box.minable = {mining_time = 0.2, result = "trade-box"}
trade_box.localised_name = {"entity-name.trade-box"}
trade_box.localised_description = {"entity-description.trade-box"}
trade_box.inventory_type = "with_filters_and_bar"
trade_box.inventory_size = 32
trade_box.icons = {
  {
    icon = "__base__/graphics/icons/steel-chest.png",
    icon_size = 64,
    tint = accent_tint,
  },
  {
    icon = "__base__/graphics/icons/coin.png",
    icon_size = 64,
    scale = 0.45,
    shift = {10, 10},
  },
}
trade_box.icon = nil
for _, layer in ipairs(trade_box.picture.layers) do
  if not layer.draw_as_shadow then
    layer.tint = accent_tint
  end
end

data:extend({trade_box})
