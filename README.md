# Alone At Ocean

Projeto de sobrevivência e construção em uma jangada, feito em Godot 4.7.2. Inclui jogo solo e sessões cooperativas por conexão direta.

## Como começar

Abra o projeto no Godot 4.7.2 e execute `Scenes/World/World.tscn`. A partida agora inicia automaticamente em modo solo, sem lobby, HUD, menus, controles na tela, retículo, relógio visual ou nomes flutuantes. Para criar ou entrar em uma sessão online, recrie uma tela e conecte-a ao `NetworkManager` descrito abaixo.

## Controles que continuam ativos

- **WASD** ou analógico esquerdo: mover; **mouse** ou analógico direito: olhar; **Espaço / botão inferior**: pular; **Shift / L3**: correr; **Ctrl / círculo**: agachar.
- **E / quadrado**: coletar o recurso mirado; **F / direcional para cima**: comer; **G / direcional para baixo**: beber água.
- Construção: o sistema em rede aceita os modos **1** construir, **3** demolir e **6** reparar. **R** gira; **Enter / botão inferior** confirma; clique esquerdo executa a ação; clique direito ou **Esc** cancela. **[** e **]** percorrem as peças do catálogo.
- **Esc** mantém a função de liberar o mouse durante o jogo.

As ações **`inventory`** (I / Triângulo), **`build_menu`** (V / OPTIONS), **`settings_menu`** (F2 / botão MISC1 do controle), **`hotbar_wood`** (Z), **`hotbar_plastic`** (X), **`hotbar_scrap`** (C), **`hotbar_previous`** (gatilho L2), **`hotbar_next`** (gatilho R2) e **`build_select_1`–`build_select_4`** (1–4) continuam mapeadas em `project.godot` (a ação de configurações é garantida por `Scripts/UI/game_settings.gd`). Elas não abrem nem atualizam telas enquanto você não recriar os respectivos componentes visuais e conectar os sinais/ações. A tecla **T** também não abre mais o chat; o chat continua disponível por código.

## Onde recriar as interfaces

As cenas antigas foram removidas de `Scenes/UI/`; recrie as cenas nessa pasta e instancie-as em `Scenes/World/World.tscn` ou a partir do nó indicado. `Assets/UI/` foi preservada, assim como todos os assets de gameplay e os addons.

| Interface que você quiser recriar | Cena sugerida | Lógica existente para conectar |
| --- | --- | --- |
| Lobby, anfitrião/entrada por IP, jogadores e chat | `Scenes/UI/SessionInterface.tscn`, instanciada como filha de `World` | `Scripts/Multiplayer/network_manager.gd`: `create_host(nome)`, `join_game(ip, nome)`, `start_offline(nome)`, `disconnect_game()`, `send_chat_message(text)`; sinais `session_started`, `session_ended`, `player_list_changed`, `session_status_changed` e `chat_message_received`. A partida já começa solo; `create_host` e `join_game` trocam essa sessão solo pela solicitada. |
| Vida, fome, sede, fôlego, inventário, hotbar, retículo e feedback de coleta | `Scenes/UI/SurvivalHUD.tscn`, filha de `World` | Dados do jogador em `Scripts/Player/player.gd` (`health`, `hunger`, `thirst`, `stamina`, contagens de itens); coleta/consumo em `Scripts/Survival/survival_manager.gd` e `player.gd`. O grupo de jogadores é `players`. |
| Catálogo e comandos de construção | `Scenes/UI/BuildMenu.tscn`, dentro da nova HUD | O sistema é criado por `Scenes/Building/BuildingKitBootstrap.gd` e acessado em `World/BuildingKitSetup.build_system`; catálogo em `Scenes/Building/BuildingCatalog.gd`; chamadas de seleção/modo e rede em `Scripts/Multiplayer/networked_build_system.gd`. O Building Kit continua com entrada por teclado/controle, sem a HUD visual. |
| Inventário e controles de toque | `Scenes/UI/InventoryScreen.tscn` e `Scenes/UI/MobileControls.tscn`, dentro da nova HUD | O inventário fica nos campos do `SurvivalPlayer`; para toque, `player.gd` mantém `set_touch_move`, `set_touch_jump`, `set_touch_sprint` e `apply_touch_look`. |
| Configurações | `Scenes/UI/SettingsMenu.tscn`, dentro da nova HUD | O autoload `GameSettings` em `Scripts/UI/game_settings.gd` preserva preferências gráficas e estados usados para bloquear entrada durante menus. |
| Relógio dia/noite | `Scenes/UI/DayNightHUD.tscn`, filha de `World` | `Scripts/World/day_night_cycle.gd` mantém o ciclo e publica `clock_updated(is_day, clock_minutes, seconds_until_transition)`; também oferece `get_clock_state()`. |

Para um chat, chame `NetworkManager.send_chat_message(text)` e conecte `chat_message_received`. Para atualizar lista/status da sessão, conecte `player_list_changed` e `session_status_changed`.

## Sistemas incluídos

- Movimento de jogadores e sessões cooperativas por conexão direta, com autoridade do anfitrião, até 8 jogadores e porta UDP 7000.
- Construção cooperativa de pisos, paredes, rampas e tetos, validada pelo anfitrião; novos jogadores recebem o estado da jangada.
- Recursos à deriva; coleta ao mirar e pressionar **E**; comida e água recuperam necessidades, e fome/sede zeradas causam dano.
- Ciclo de dia/noite de 24 minutos por sessão: 12 minutos de dia e 12 de noite, sincronizado pelo anfitrião.

## Limites atuais

Não há salvamento persistente, matchmaking, servidor de relay ou travessia automática de NAT. Para conexões pela internet, o anfitrião normalmente precisa liberar e encaminhar a porta **UDP 7000**. A construção por arrasto não está habilitada no multiplayer; coloque uma peça por vez.
