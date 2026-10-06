# Limitações conhecidas

## Limitações técnicas

| # | Limitação | Impacto | Classificação |
|---|---|---|---|
| PLAT-01 | Windows e Linux **não foram compilados nem executados** (ambiente disponível: só macOS). Runners, tamanho mínimo de janela e cofres de credenciais estão configurados. | Pode haver ajustes de build nessas plataformas. | IMPORTANT |
| LIVE-01 | Nenhum teste contra um homeserver Matrix real foi executado (sem credenciais no ambiente). Todo o fluxo foi validado contra um homeserver falso local. O teste live existe (`tests/live_login.rs`, ignorado). | Diferenças de comportamento entre o mock e servidores reais podem existir. | IMPORTANT |
| E2EE-01 | Salas criptografadas **não validadas** em servidor real. O SDK cuida da criptografia; mensagens que não puderam ser descriptografadas não são exibidas. | Comportamento real em salas cifradas não comprovado. | IMPORTANT |
| SEC-02 | Builds de desenvolvimento no macOS têm assinatura ad-hoc: após recompilar, o macOS pode pedir permissão para o app ler um item do Keychain criado pelo build anterior. Builds assinados com a mesma identidade não têm esse efeito. | Só desenvolvimento. | NON-BLOCKER |
| SEC-03 | Linux exige um provedor de Secret Service em execução (gnome-keyring, KWallet). Sem ele, o login falha ao persistir a sessão (sem fallback para arquivo em texto puro, por segurança). | Ambientes Linux mínimos. | NON-BLOCKER |
| NET-02 | Login usa a política de retry do próprio SDK (3 tentativas de 30 s): um servidor que aceita a conexão e não responde pode deixar o login em "Entrando…" por até ~90 s. Demais chamadas: ~10 s. | Caso raro. | NON-BLOCKER |
| BUILD-01 | O crate Rust é compilado mais de uma vez: pelo `cargo` (testes) e pelo build hook (em `.dart_tool`, release). Unificar exigiria scripts frágeis. | Só tempo de build. | NON-BLOCKER |
| FRB-01 | No FRB 2.13, cancelar uma assinatura de `Stream` só conclui no próximo evento. O app mantém uma assinatura por motor e fecha o stream com `dispose()`. | Nenhum no app; documentado para quem usar a API. | NON-BLOCKER |
| SYNC-02 | Após mais de 50 eventos numa sala entre dois syncs, o core sinaliza lacuna e a conversa aberta é recarregada (últimas 50 mensagens); mensagens antigas além disso não são buscadas. | Histórico limitado às mensagens recentes. | NON-BLOCKER |
| NET-03 | Um token revogado só é detectado na primeira requisição real (a restauração não usa rede). | Ao abrir offline com token revogado, o app mostra a sessão até reconectar. | NON-BLOCKER |
| UI-01 | Navegação da lista de salas por teclado usa o padrão do Flutter (Tab, setas); não há atalhos Home/End nem "foco no composer ao abrir a sala". | Acessibilidade de teclado básica. | NON-BLOCKER |

## Fora de escopo (não implementado por decisão)

Contagem de não lidas, ordenação por atividade (lista em ordem alfabética),
paginação do histórico além das mensagens recentes, mensagens que não sejam
`m.text` (mídia, notices, emotes, edições, respostas, threads, reações),
convites e criação/entrada em salas, indicador de digitação, confirmações de
leitura, notificações, busca, perfil/avatar, múltiplas contas, cadastro, SSO.
