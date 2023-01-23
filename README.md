# Description

This is a taunts menu plugin similar to [TF2 Taunts TF2IDB](https://github.com/fakuivan/TF2-Taunts-TF2IDB).

Obviously, as the name implies, it uses [TFEconData](https://github.com/nosoop/SM-TFEconData) and it also features somewhat functional unusual taunts.

# Commands

  | Commands           | Description                                                                                  |
  |--------------------|--------------------------------------------------------------------------------------------- |
  | `sm_taunt`         | Displays the taunts menu. Follow the command with a valid taunt ID to automatically play it. |
  | `sm_taunts`        | Alternative to `sm_taunt`                                                                    |
  | `sm_unusualtaunt`  | Displays the unusual taunt particles menu                                                    |
  | `sm_unusualtaunts` | Alternative to `sm_unusualtaunt`                                                             |
  | `sm_utaunt`        | Alternative to `sm_unusualtaunt`                                                             |
  | `sm_utaunts`       | Alternative to `sm_unusualtaunt`                                                             |
  | `sm_refreshtaunts` | Reloads the taunts configuration file                                                        |

# ConVars

  | ConVars                       | Description                                                                    | Default value    |
  |-------------------------------|--------------------------------------------------------------------------------|------------------|
  | `sm_econtaunts_refire`        | Time variation between particle restarts. (necessary for info_particle_system) | `0.05` (seconds) |
  | `sm_econtaunts_defaulttaunts` | Add unusuals to default taunts?                                                | `0` (disabled)   |

# Issues

* Some taunt particles are not positioned correctly.
* Some taunt particles leave remnants after the taunt has ended.
* Taunt particles that refire will not do so (unless specified in the [`unusual taunts configuration`](https://github.com/x07x08/TF2-Econ-Taunts/tree/main/addons/sourcemod/configs/econtaunts) file).

If there are any other issues, please report them using the [Issues](https://github.com/x07x08/TF2-Econ-Taunts/issues) tab.

# Installation

1. Install [TFEconData](https://github.com/nosoop/SM-TFEconData).
2. Download the plugin (go to [releases](https://github.com/x07x08/TF2-Econ-Taunts/releases) or clone the repository).
3. Drag and drop the files into your server's `tf` directory.
4. If some (or all) taunt props are not visible, also install [this](https://forums.alliedmods.net/showpost.php?p=2796688&postcount=19).

# Credits

1. [Taunt 'em](https://forums.alliedmods.net/showthread.php?p=2157489) by FlaminSarge. ([Alt. Link](https://github.com/FlaminSarge/tf_tauntem))
2. "[TF2 Item Management Plugins](https://github.com/punteroo/TF2-Item-Plugins)" by punteroo.
3. [TFEconData](https://github.com/nosoop/SM-TFEconData) by nosoop.
4. [TF2 Unusual Taunts](https://forums.alliedmods.net/showthread.php?p=2722944) by StrikeR14. ([Alt. Link](https://github.com/nushnush/TF2-Unusual-Taunts))
