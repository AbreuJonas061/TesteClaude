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

Rotinas **ADVPL** para o **Protheus 12.1.2410**. Cada rotina é um fonte único,
cadastrado no menu (SIGAMDI). Nenhuma usa Schedule/Job.

| Caminho | Conteúdo |
|---|---|
| `src/IMPPRD01.prw` | `zImpPro` — importação de produtos (tela + processamento) |
| `src/AUDEST01.prw` | `zAudEst` — auditoria de roteiro/estrutura (tela + query + relatório) |
| `docs/MANUAL.md` | Manual do `zImpPro` |
| `docs/MANUAL_AUDEST.md` | Manual do `zAudEst` |
| `exemplos/` | Arquivos CSV/TXT de exemplo nos dois modos de layout |

### zImpPro — decisões de arquitetura que devem ser preservadas

- **Gravação exclusivamente por `MSExecAuto` + `MATA010`.** Nunca gravar com
  `RecLock`/`Replace` — o objetivo da rotina é justamente passar por todas as
  validações nativas (`X3_VALID`, gatilhos, pontos de entrada).
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

Três funções no início do fonte concentram o que normalmente se altera:

```advpl
IP01Layout()   // ordem das colunas no modo sem cabeçalho
IP01Fixos()    // valores fixos aplicados a todos os registros
IP01Ignora()   // colunas do arquivo que devem ser desprezadas
```

### zAudEst — decisões de arquitetura que devem ser preservadas

- **Somente leitura.** Nenhum `INSERT`/`UPDATE`/`DELETE`, nenhuma gravação em
  tabela do Protheus. O único efeito é a criação dos arquivos de saída.
- **A query da engenharia é a fonte da verdade.** A CTE recursiva, a vigência
  (`G1_INI`/`G1_FIM`), a faixa de revisão (`G1_REVINI`/`G1_REVFIM`) e os `EXISTS`
  de SG1/SG2 ficam no SQL, em `AE01Sql()`, iguais ao original.
- **`Situacao`/`Motivo` são transcrição literal dos `CASE`**, em `AE01Class()`, na
  mesma ordem de avaliação. A ordem é a regra — não reordenar as cláusulas.
- **`TemFilho` não volta para o SQL.** Lá era um `EXISTS` contra a própria CTE
  recursiva, e o SQL Server reexecuta a recursão a cada linha.
- **Relatório em HTML gerado pela própria rotina**, com o texto fixo em entidades
  HTML — assim a acentuação não depende da codificação do AppServer.

Três funções no início do fonte concentram o que normalmente se altera:

```advpl
AE01Chapas()   // 15 códigos de chapa e o peso de uma chapa 3000x1200
AE01Regras()   // por tipo: quando exige roteiro e quando é folha válida
AE01Criter()   // textos do quadro "CRITÉRIOS DE ANÁLISE"
```

---

## Preferências de trabalho

- Jonas é analista de sistemas: programa em **ADVPL** e usa bastante **SQL Server**.
- Respostas e comentários de código em **português**.
- Ao explicar algo do Protheus, considerar consultas SQL de apoio (SX3, SX5,
  SB1) — costumam ser mais úteis que descrições genéricas.
- O fonte não pode ser compilado neste ambiente (não há AppServer). Ao alterar
  ADVPL, revisar com cuidado e avisar que a validação final é na compilação.
