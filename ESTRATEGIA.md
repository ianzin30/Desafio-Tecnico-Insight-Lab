# Estratégia de implementação

> Mínimo viável para a conclusão inicial do desafio técnico

## 1. Entender o desafio antes de implementar

A primeira etapa foi transformar o enunciado em um conjunto objetivo de capacidades. O propósito era construir um MVP com um fluxo completo: entrar, visualizar salas, abrir uma conversa, ler, enviar e receber mensagens, encerrar o aplicativo e recuperar a sessão na próxima abertura. Tal lógica, claro, mapeou etapas fundamentais como segurança dos tokens de sessão e mensagens, como etapa de hardening posterior ao esqueleto inicial da aplicação. 

Esse mapeamento também serviu para separar requisitos de possibilidades. Criar salas e cadastrar contas foram considerados inicialmente, mas não incorporados ao escopo mínimo. A mesma contenção valeu para anexos, reações, notificações e outras funcionalidades de um mensageiro completo. 

Portanto, a dificuldade existente na compreensão do problema é centrada em conseguir "congelar" uma documentação para implementação rápida e incremental. Então, devemos pensar em funcionalidades, no caso, capacidades que precisam existir no sistema:

| Capacidade | Recorte adotado |
|---|---|
| Autenticação | Login com homeserver, usuário e senha; logout e restauração de sessão. |
| Salas | Listagem das salas das quais o usuário participa e seleção de conversa. |
| Mensagens | Carregamento, envio de texto e recebimento em tempo real. |
| Persistência | Continuidade da sessão e armazenamento local utilizado pelo SDK. |
| Desktop | Interface Flutter e preparação para macOS, Linux e Windows. |

**Critério de prioridade:** primeiro garantir o percurso principal; depois fortalecer falhas, segurança e entrega. Funcionalidades adicionais, mesmo que para excelente UX, à primeira ordem são trabalho futuro.

## 2. Divisão de responsabilidades

Utilizando, portanto, como base as capacidades anotadas acima, a etapa seguinte deve separar o trabalho que será selecionado para cada camada da aplicação:

| Camada | Responsabilidade |
|---|---|
| **Flutter** | UI/UX, navegação, formulários, estados visuais, teclado e adaptação da janela desktop. |
| **Riverpod** | Coordenar autenticação, salas e conversa; centralização de eventos. |
| **Flutter Rust Bridge** | Comunicação Dart e Rust. |
| **Core Rust** | Controlar o ciclo de vida do cliente, autenticação, sessão, operações de mensagens e sincronização. |
| **Matrix Rust SDK** | Comunicação com o homeserver e mecanismos do protocolo e de armazenamento usados pelo core. |

O Flutter não precisa interpretar respostas HTTP do Matrix nem conhecer os tipos internos do SDK. A fronteira usa DTOs e erros com significado para a aplicação. Isso reduz o acoplamento e permite desenvolver e testar o core antes da interface.

## 3. Implementação incremental por lotes

A ordem, então, seguiu as dependências reais do produto: estabelecer o core, provar o fluxo de mensageria, conectar o Flutter e só então construir a experiência visual. Cada lote deveria produzir uma base verificável para o seguinte. 

Cada etapa está dividida, portanto, na codebase, via um commit específico para si, cada uma com testes respectivos à sua funcionalidade.

### 01 — Inicialização do core Rust

Preparação do workspace e das dependências centrais da integração: Matrix Rust SDK e Flutter Rust Bridge. O foco inicial foi estabelecer uma base compilável e uma organização que permitisse evoluir o domínio.

### 02 — Comunicação Matrix e cliente central

Configuração do homeserver e construção do cliente central. Um único `matrix_sdk::Client` por core evita recriar conexões, armazenamento e estado de autenticação a cada operação. O homeserver pertence à configuração dessa instância.

### 03 — Autenticação mínima

Implementação do login e do tratamento de falhas de autenticação. A validação efetiva permanece no Rust/SDK; a camada Flutter apresenta o resultado sem duplicar regras do protocolo.

### 04 — Sessão e armazenamento persistente

Persistência e restauração da sessão, armazenamento SQLite utilizado pelo SDK e logout. Essa etapa, claro, permite que fechar a janela não obrigue o usuário a se autenticar novamente. Embora importante, uma dívida desse lote foi não adentrar em criptografia, por ora. Esse fato foi registrado como dívida.

### 05 — Descoberta e listagem de salas

Exposição das salas com participação ativa do usuário, com os dados necessários para a navegação. Convites e Spaces ficaram fora dessa listagem. A interface passou a consumir uma representação própria, sem depender dos objetos internos do SDK.

### 06 — Carregamento e envio de mensagens

Construção do fluxo de leitura e envio de texto. O recorte inicial usa uma janela limitada de eventos, sem paginação de histórico completo. Como eventos Matrix também representam alterações de estado e outros conteúdos, recuperar 50 eventos não garante exibir 50 mensagens.

### 07 — Sincronização contínua

Manutenção do sync e emissão de eventos para mudanças de salas, mensagens, conexão e sessão. 

### 08 — Consumo pelo Flutter

Integração da API tipada e do stream de eventos pela bridge. Os testes usam o Rust real contra um homeserver falso local, verificando a fronteira Dart/Rust sem depender da internet ou de contas externas.

### 09 — Lógica de estados Flutter

Adoção do Riverpod e de um `MessengerController` como coordenador de autenticação, salas e conversa. Um único dono desses estados facilita tratar acontecimentos que afetam toda a aplicação, como logout ou revogação da sessão.

Essa camada também protege contra respostas atrasadas após troca de sala ou encerramento da sessão, agrupa recargas concorrentes e preserva mensagens recebidas durante carregamentos. A escolha dinâmica do homeserver exige recriar o gateway quando necessário, preservando uma única API e uma única assinatura de eventos ativas.

### 10 — Prototipação e implementação da interface

A prototipação foi realizada iterativamente no Claude Design, começando por wireframes e evoluindo para alta fidelidade. A implementação Flutter utilizou a board diretamente via MCP como referência visual.

[**Abrir o protótipo — wireframe e alta fidelidade**](https://claude.ai/artifact/BVZGq8rGsJcREcGiQYMSjX#play-b53e53ad5e72)

O seletor no canto superior esquerdo permite alternar as versões do protótipo. A UI abrange login, lista de salas, conversa e composer, incluindo estados de carregamento, erro e conexão.

### 11 — Hardening, harness e preparação da entrega

A etapa final concentra robustez, segurança, validação multiplataforma e documentação. O harness de testes já utilizado nas camadas anteriores serve de base para reproduzir falhas e corridas de forma controlada. Além disso, nessa etapa foi também feita o ajuste de UI para um ícone personalizado e o nome do app trocado para "Insight Lab"



## 4. Principais decisões e seus motivos

| Decisão | Justificativa e consequência |
|---|---|
| **Construir o core antes da UI** | Permite verificar o fluxo Matrix isoladamente e depois, por cima, implementar o protótipo. |
| **Centralizar Matrix no Rust** | Evita duas implementações das regras do protocolo. |
| **Manter um único coordenador de estado** | Logout, revogação e remoção de sala afetam várias partes da tela. Um cliente único reduz problemas. |
| **Descartar resultados obsoletos** | Uma resposta da sala anterior ou de uma sessão encerrada não pode sobrescrever o estado atual. |
| **Recriar o core ao mudar o homeserver** | O servidor está associado à instância, ao trocar, o estado é reiniciado. |
| **Conter o escopo funcional** | Prioriza um percurso confiável em vez de aumentar a superfície de implementação e testes, configurando uma entrega sucinta, porém dentro do escopo e explicável. |

## 5. Estratégia de validação

A validação acompanha a implementação, com diferentes níveis de evidência:

- **Rust:** regras do core, autenticação, persistência, mensagens e sync.
- **Bridge e aplicação:** gateway real com homeserver falso, incluindo atrasos por sala, falhas e corridas controladas.
- **Widgets:** comportamento visual, interação e estados da interface.
- **Integração desktop:** funcionamento conjunto do aplicativo e da bridge, além do build release.
- **Ambiente real:** complementar os testes locais com homeserver e sala criptografada quando houver ambiente disponível.

Os testes padrão devem continuar independentes de internet. Eventos difíceis de provocar deterministicamente pelo stack completo, como `EventsLost`, podem ser injetados em pontos de teste explícitos. Isso valida a reação do controller, sem substituir a validação do transporte real.

## 6. Pendências, limites e trabalho futuro

Como trabalho futuro, foi catalogada a seguinte importante pendência como hardening importante ainda não realizado:

| **E2EE real** | Validar em sala criptografada real. |


Porém, como implementações de UI/UX, temos as seguintes abaixo que não foram feitas, mas são importantíssimas também:

Criação de salas, cadastro, anexos, reações, notificações, contagem de não lidas e ordenação por atividade. Não são falhas do MVP por si só, apenas o resultado de, claro, congelar o escopo para uma entrega v0 efetiva e com possibilidade incremental.

