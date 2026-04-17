local constants = {
  mod_name = "factorio-trade-mode",
  storage_version = 1,

  entity_name = "trade-box",
  item_name = "trade-box",
  shortcut_name = "trade-mode-open-panel",
  custom_input_name = "trade-mode-toggle-market",

  setting_enable_chart_tags = "trade-mode-enable-chart-tags",

  gui = {
    screen_root = "trade_mode_screen_root",
    main_tabs = "trade_mode_main_tabs",
    market_filter = "trade_mode_market_filter",
    market_online_only = "trade_mode_market_online_only",
    market_results = "trade_mode_market_results",
    market_orders_table = "trade_mode_market_orders_table",
    contract_title = "trade_mode_contract_title",
    contract_description = "trade_mode_contract_description",
    contract_amount = "trade_mode_contract_amount",
    contract_list = "trade_mode_contract_list",
    contract_count = "trade_mode_contract_count",
    contract_feedback = "trade_mode_contract_feedback",
    contract_list_prefix = "trade_mode_contract_select_",
    buy_order_item = "trade_mode_buy_order_item",
    buy_order_price = "trade_mode_buy_order_price",
    buy_order_feedback = "trade_mode_buy_order_feedback",
    buy_order_fill_suggested = "trade_mode_buy_order_fill_suggested",
    buy_order_save = "trade_mode_buy_order_save",
    buy_order_cancel = "trade_mode_buy_order_cancel",
    buy_order_toggle = "trade_mode_buy_order_toggle",
    buy_order_delete = "trade_mode_buy_order_delete",
    trade_box_root = "trade_mode_trade_box_root",
    contract_create = "trade_mode_contract_create",
    contract_assign = "trade_mode_contract_assign",
    contract_unassign = "trade_mode_contract_unassign",
    contract_pay = "trade_mode_contract_pay",
    market_tab = "trade_mode_market_tab",
    contracts_tab = "trade_mode_contracts_tab",
    economy_tab = "trade_mode_economy_tab",
    admin_tab = "trade_mode_admin_tab",
    selected_contract = "trade_mode_selected_contract",
    inserter_panel = "trade_mode_inserter_panel",
  },

  ubi = {
    base_income = 2,
    income_scale = 0.08,
    income_exponent = 0.85,
  },

  ore_names = {
    "iron-ore",
    "copper-ore",
    "coal",
    "stone",
    "uranium-ore",
  },

  ticks = {
    second = 60,
    ui_refresh = 30,
  },
}

return constants
