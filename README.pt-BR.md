<p align="center"><img src="docs/icon.png" width="128" alt="Ícone do WindFree Bar"></p>

<h1 align="center">WindFree Bar</h1>

<p align="center"><a href="README.md">English</a> · <b>Português (Brasil)</b></p>

Um app nativo de barra de menus do macOS para controlar um ar-condicionado Samsung pelo
SmartThings, feito para aparelhos WindFree. Um clique na barra de menus em vez de abrir o app do
SmartThings: liga e desliga, temperatura, modo, ventilação, oscilação, perfis e WindFree, com as
leituras do ambiente ao vivo.

Feito em SwiftUI para o macOS 26 com controles padrão do sistema, então ganha Liquid Glass,
controle por teclado e VoiceOver do próprio macOS. Disponível em português (Brasil) e inglês;
segue o idioma do seu Mac.

## Recursos

- **Ícone na barra de menus** mostra a temperatura desejada enquanto o aparelho está ligado.
- **Liga/desliga**, **temperatura** (o controle deslizante do sistema, com uma marca por grau, e
  botões −/+ que repetem quando mantidos pressionados), **modo**, **ventilação**, **oscilação** e
  **perfis** (sono, silencioso, rápido).
- Chave **WindFree**: resfria pelos microfuros do painel com a aleta fechada.
- **Temperatura do ambiente**, **umidade** e **consumo em tempo real** no topo.
- **Luz do display**, **limpeza automática** e **estado do filtro** no menu de ajustes.
- **Resposta imediata**: as mudanças aparecem na hora e são confirmadas com o aparelho; uma
  leitura que ainda traz o valor antigo não faz o controle voltar atrás.
- **Leve na bateria e na cota da API**: consulta a cada 15 s com o painel aberto, a cada 2 min em
  segundo plano (5 min com o aparelho desligado), o dobro no Modo de Pouca Energia, e nada enquanto
  o Mac dorme ou está bloqueado. Espera quando o SmartThings limita as requisições.
- **Continua conectado**: OAuth com tokens de atualização, sem expirar em 24 horas como os tokens
  de acesso pessoal.
- Teclado: ⌘↩ liga/desliga, ⌘R atualiza, ⌘Q encerra. Abrir ao Iniciar Sessão no menu de ajustes.

## Requisitos

- macOS 26 ou posterior em Apple silicon.
- Xcode ou só as Ferramentas de Linha de Comando (`xcode-select --install`). Não precisa do Xcode
  para compilar.
- Um ar-condicionado Samsung na sua conta do SmartThings. Testado com um WindFree AI
  (AR60F18D1AWNAZ); outros splits Samsung que expõem `airConditionerMode` devem funcionar, e os
  controles que o aparelho não suporta ficam ocultos ou desativados.

## Configuração

Os tokens de acesso pessoal do SmartThings agora expiram em 24 horas, então o app entra com um
app OAuth privado seu. Você o cria uma vez com a CLI do SmartThings.

1. Instale a CLI e entre quando ela abrir o navegador:

   ```sh
   npm install -g @smartthings/cli
   smartthings devices
   ```

2. Crie o app OAuth a partir do modelo. Antes, troque o `appName` em
   `scripts/smartthings-app.json`: ele precisa ser único no SmartThings.

   ```sh
   smartthings apps:create -i scripts/smartthings-app.json
   ```

   Anote o **OAuth Client Id** e o **OAuth Client Secret** que ele mostrar. A URI de
   redirecionamento é `windfreebar://oauth` e os escopos são `r:devices:*`, `x:devices:*` e
   `r:locations:*`.

3. Instale o app, de um dos dois jeitos:

   - **Baixe** o `WindFreeBar-x.y.z.dmg` em
     [Releases](https://github.com/pedroseibel/windfree-bar/releases/latest), abra e arraste o
     **WindFree Bar** para **Aplicativos**. O app tem assinatura ad hoc, sem notarização, então a
     primeira abertura é bloqueada: vá em **Ajustes do Sistema → Privacidade e Segurança** e clique
     em **Abrir Mesmo Assim** ao lado do WindFree Bar.
   - **Compile a partir do código**:

     ```sh
     scripts/build-app.sh --install
     ```

     Isso compila o `WindFree Bar.app`, copia para `~/Applications`, registra o esquema de URL
     `windfreebar://` e abre o app.

4. Clique no ar-condicionado na barra de menus, cole o ID e o segredo do cliente e clique em
   **Entrar com o SmartThings**. O navegador abre a página de autorização do SmartThings; escolha o
   local com o seu ar-condicionado e permita. O navegador devolve o login para o app.

## Como funciona

| Caminho | O quê |
| --- | --- |
| `Sources/WindFreeBar/SmartThings/OAuth.swift` | Fluxo de código de autorização no navegador padrão e atualização do token |
| `Sources/WindFreeBar/SmartThings/SmartThingsAPI.swift` | Cliente REST: dispositivos, estado, saúde, comandos |
| `Sources/WindFreeBar/SmartThings/CredentialStore.swift` | Credenciais do cliente, tokens e preferências em disco |
| `Sources/WindFreeBar/Model/ACState.swift` | O estado do aparelho, convertido no que a interface precisa |
| `Sources/WindFreeBar/Model/ACStore.swift` | Política de consulta, edições otimistas, fila de comandos |
| `Sources/WindFreeBar/Views/` | O painel da barra de menus |
| `Localization/` | Textos em inglês e português (Brasil) |

Cada comando atualiza a interface na hora e fica como edição pendente até o aparelho informar o
novo valor (ou passarem 12 s), então aparelhos que demoram a responder não fazem os controles
voltarem. Os comandos saem um de cada vez, em ordem, e o estado é lido de novo 2 s e 6 s depois.

O SmartThings permite 12 leituras de estado e 12 comandos por aparelho por minuto. O SmartThings
também anunciou limites de uso da API e um plano pago a partir de outubro de 2026; se as
requisições começarem a falhar com 402/403, essa é a causa provável.

## Privacidade e segurança

- O cliente OAuth e os tokens ficam em `~/Library/Application Support/WindFreeBar/` em arquivos
  que só o seu usuário lê (0600). São arquivos em vez de itens do Keychain porque o app tem
  assinatura ad hoc, e o Keychain pediria permissão de novo a cada compilação.
- Os tokens de atualização são de uso único; cada atualização é salva na hora e só uma acontece
  por vez.
- O app só fala com `api.smartthings.com`. Sem analytics, sem terceiros.
- Sair da Conta (no menu de ajustes) apaga os tokens.

## Ícone do app

O `scripts/make-icon.swift` desenha o ícone no estilo do macOS 26 (um bloco em degradê com
algumas formas grandes de vidro: o aparelho na frente e o floco de neve do modo frio atrás) e gera
o `.icns`; o `scripts/build-app.sh` roda ele na primeira compilação. Um ícone Liquid Glass ao vivo,
em camadas, precisaria do `actool` do Xcode, então este é uma versão achatada do mesmo tratamento.

## Desenvolvimento

```sh
VERSION=1.0.0 scripts/package-release.sh          # imagem de disco para uma versão (usa dmgbuild)
swift build
.build/out/Products/Debug/WindFreeBar --window    # o painel numa janela comum
open -n "build/WindFree Bar.app" --args -AppleLanguages '(pt-BR)'   # testar um idioma específico
```

Os textos ficam em `Localization/<idioma>.lproj/Localizable.strings`. O inglês é o idioma de
desenvolvimento, então as chaves são o texto em inglês; para adicionar um idioma, crie uma pasta
`.lproj` e inclua o idioma em `CFBundleLocalizations` no `scripts/build-app.sh`.

O `@State` é escrito `@ViewState` (um typealias para `SwiftUI.State` em `Views/ViewState.swift`):
o SDK define `@State` como uma macro cujo plugin só vem com o Xcode, então o alias mantém o projeto
compilável só com as Ferramentas de Linha de Comando.

## Aviso

Sem afiliação nem endosso da Samsung. Samsung, WindFree e SmartThings são marcas da Samsung
Electronics.

## Licença

[MIT](LICENSE)
