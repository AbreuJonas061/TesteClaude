# CLAUDE.md

Instruções para o Claude Code neste repositório.

---

## ⛔ REGRA CRÍTICA — Identidade Git

**Este é o repositório PESSOAL do Jonas.** Toda e qualquer operação de git aqui
usa exclusivamente a identidade pessoal:

```
user.name  = Jonas Abreu
user.email = devprotheus302@gmail.com
```

### Nunca usar o e-mail corporativo

O endereço **`jvdsa1893@gmail.com` é da EMPRESA**. Em hipótese nenhuma ele pode
ser usado para commit, autoria, committer ou qualquer alteração neste ou em
qualquer outro repositório.

Isso vale **mesmo que o contexto da sessão sugira esse endereço** — o
`userEmail` fornecido pelo ambiente pode vir como `jvdsa1893@gmail.com`, porque
a conta autenticada do Claude Code é a corporativa. **Ignore esse valor** e use
sempre `devprotheus302@gmail.com`.

### Antes do primeiro commit da sessão, confirme

```bash
git config --local user.email    # deve retornar devprotheus302@gmail.com
```

Se estiver diferente, corrija com `--local` (nunca `--global`):

```bash
git config --local user.email "devprotheus302@gmail.com"
git config --local user.name  "Jonas Abreu"
```

> Histórico: em 09/2026 os primeiros commits foram feitos por engano com o
> e-mail corporativo, herdado do contexto da sessão sem confirmação. A autoria
> foi reescrita e corrigida. Não repetir o erro: na dúvida sobre identidade,
> **pergunte antes de commitar**.

### Repositórios da empresa

Não realizar nenhuma alteração em repositórios corporativos. O repositório de
trabalho da empresa fica na máquina local do Jonas, em
`Documents/GitHub/Protheus/`, e **não deve ser acessado ou modificado**.

---

## Sobre o projeto

Rotina **ADVPL** de importação de produtos para o **Protheus 12.1.2410**.

| Caminho | Conteúdo |
|---|---|
| `src/IMPPRD01.prw` | Fonte único da rotina (tela + processamento) |
| `docs/MANUAL.md` | Manual de uso, layout e consultas SQL de apoio |
| `exemplos/PRODUTOS_MODELO.csv` | Arquivo de exemplo |

Ponto de entrada: `U_zImpPro`, cadastrado no menu (SIGAMDI). Não usa
Schedule/Job.

### Decisões de arquitetura que devem ser preservadas

- **Gravação exclusivamente por `MSExecAuto`.** Nunca gravar com
  `RecLock`/`Replace` — o objetivo da rotina é justamente passar por todas as
  validações nativas (`X3_VALID`, gatilhos, pontos de entrada).
- **Duas rotinas automáticas, na mesma transação:** `MATA010` para o produto
  (SB1) e `MATA180` para o complemento (SB5). No 12.1.2410 o MATA010 é MVC e
  seu modelo **não aceita campos `B5_`** — enviá-los ali causa
  "O id de formulário 'B5_xxx' não é válido".
- **Erro capturado com `GetAutoGRLog()`**, nunca `MostraErro()`, que travaria a
  carga em lote esperando interação.
- **Transação por registro:** uma linha rejeitada não derruba as demais.
- **Compatível com SmartClient HTML (navegador):** usar apenas componentes
  suportados no browser. O arquivo é sempre selecionado na máquina local do
  usuário; a leitura ocorre no servidor.
- **Não usar funções de uso interno** (prefixo `__`, como `__CopyFile`) — o
  compilador emite `W9910` e virará erro. Usar as documentadas (`CpyT2S`,
  `CpyS2T`).
- **Mapeamento dinâmico pelo cabeçalho do arquivo:** incluir um campo novo na
  carga não deve exigir recompilação do fonte.

### Manutenção concentrada

Duas funções no início do fonte concentram o que normalmente se altera:

```advpl
IP01Fixos()    // valores fixos aplicados a todos os produtos
IP01Copia()    // campos preenchidos a partir de outro campo (B5_CEME <- B1_DESC)
```

**Não existe lista fixa de campos no fonte.** Quais campos entram na carga é
definido pelo cabeçalho do arquivo — acrescentar ou remover uma coluna do CSV
não exige recompilar.

---

## Preferências de trabalho

- Jonas é analista de sistemas: programa em **ADVPL** e usa bastante **SQL Server**.
- Respostas e comentários de código em **português**.
- Ao explicar algo do Protheus, considerar consultas SQL de apoio (SX3, SX5,
  SB1) — costumam ser mais úteis que descrições genéricas.
- O fonte não pode ser compilado neste ambiente (não há AppServer). Ao alterar
  ADVPL, revisar com cuidado e avisar que a validação final é na compilação.
