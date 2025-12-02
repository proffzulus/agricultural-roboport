data:extend({
  {
    type = "bool-setting",
    name = "agricultural-roboport-enable-quality",
    setting_type = "startup",
    default_value = true,
    order = "a-0"
  },
  {
    type = "int-setting",
    name = "agricultural-roboport-max-seeds-per-tick",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 1000,
    order = "a"
  },
  {
    type = "bool-setting",
    name = "agricultural-roboport-ignore-cliffs",
    setting_type = "runtime-global",
    default_value = false,
    order = "b"
  }
  ,
  {
    type = "bool-setting",
    name = "agricultural-roboport-debug",
    setting_type = "runtime-global",
    default_value = false,
    order = "b-1"
  }
  ,
  {
    type = "int-setting",
    name = "agricultural-roboport-tdm-period",
    setting_type = "runtime-global",
    default_value = 300,
    minimum_value = 30,
    maximum_value = 3600,
    order = "c"
  },
  {
    type = "int-setting",
    name = "agricultural-roboport-tdm-tick-interval",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 300,
    order = "d"
  }
  ,
  {
    type = "int-setting",
    name = "agricultural-roboport-seed-checks-per-call",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 1000,
    order = "e"
  },
  {
    type = "int-setting",
    name = "agricultural-roboport-max-harvest-per-call",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 100,
    order = "f"
  }
  ,
  {
    type = "int-setting",
    name = "agricultural-roboport-harvest-checks-per-call",
    setting_type = "runtime-global",
    default_value = 8,
    minimum_value = 1,
    maximum_value = 1000,
    order = "g"
  }
  ,
  {
    type = "double-setting",
    name = "agricultural-roboport-quality-proc-multiplier",
    setting_type = "runtime-global",
    default_value = 1.0,
    minimum_value = 0.0,
    maximum_value = 100.0,
    order = "h"
  }
})

