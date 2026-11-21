# Alone At Ocean

Projeto de sobrevivência e construção em uma jangada, feito em Godot 4.7.2. Inclui jogo solo e sessões cooperativas por conexão direta.

## Como começar

Abra o projeto no Godot 4.7.2 e execute a cena principal. No lobby, escolha **Jogar sozinho** para uma partida local, **Criar sessão** para ser o anfitrião ou informe o IP do anfitrião e escolha **Entrar por IP**. Cada sessão aceita até 8 jogadores, contando o anfitrião.

Para testar na mesma rede, os clientes devem usar o IP local do anfitrião. Para conexões pela internet, o anfitrião precisa liberar a porta **UDP 7000** no firewall e, normalmente, encaminhá-la no roteador ao computador que está hospedando. O jogo não possui matchmaking, servidor de relay nem travessia automática de NAT; é necessário fornecer um IP que os clientes consigam alcançar.

## Controles

- **WASD**: mover; **mouse**: olhar; **Espaço**: pular.
- **T**: abrir o chat; **Enter** envia a mensagem; **Esc** fecha o chat.
- **E**: coletar um recurso que esteja na mira; **F**: consumir comida; **G**: beber água.
- No HUD de construção, escolha a peça no catálogo e clique com o botão esquerdo para construí-la. **R** gira a peça e o botão direito cancela a colocação.
- Modos de construção disponíveis: construir (**1**), demolir (**3**) e reparar (**6**). A barra de modos também pode ser usada com o mouse.
- **Sair** encerra a sessão e retorna ao lobby.

## Sistemas incluídos

- Lobby para jogo solo, criação de sessão e entrada por IP, com nome do jogador e lista da sessão.
- Movimento de jogadores replicado pelo anfitrião, nomes visíveis, chat da sessão e entrada de jogadores em andamento.
- Construção cooperativa: pisos, paredes, rampas e tetos; colocação, demolição e reparo passam por validação do anfitrião, e quem entra depois recebe o estado da jangada.
- Recursos à deriva que o anfitrião cria e replica; ao mirar e pressionar **E**, o jogador os coleta para um inventário compartilhado na sessão.
- HUD de fome, sede, saúde e inventário. Fome e sede diminuem com o tempo; comida e água recuperam as necessidades, e valores zerados causam dano.
- Slots de entrada atribuídos pelo anfitrião e distribuídos sobre a jangada inicial.
- Ciclo de dia/noite de 24 minutos por sessão: 12 minutos de dia e 12 de noite, usando as skyboxes Kenney e sincronizado pelo anfitrião.

## Limites atuais

A sessão usa ENet diretamente na porta UDP 7000 e o anfitrião é a autoridade do mundo, do inventário e das construções. Não há salvamento persistente de sessões, inventário ou recursos, matchmaking, relay, convite automático ou recuperação da sessão após o anfitrião sair. A construção por arrasto do Building Kit não está habilitada no multiplayer; coloque uma peça por vez.
