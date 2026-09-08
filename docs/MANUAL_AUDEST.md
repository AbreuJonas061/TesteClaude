# zAudEst — Auditoria de Roteiro / Estrutura

Rotina ADVPL que explode a estrutura de um item (SG1), confere roteiro (SG2) e
cadastro (SB1) em toda a árvore e gera um relatório no padrão de auditoria da
engenharia.

- Fonte: `src/AUDEST01.prw`
- Ponto de entrada: `U_zAudEst`
- Protheus 12.1.2410 · SmartClient HTML (navegador) ou desktop
- Banco: **SQL Server** (a explosão usa CTE recursiva)

> **Somente leitura.** A rotina não faz `INSERT`, `UPDATE`, `DELETE` nem grava em
> tabela do Protheus. O único efeito é a criação dos arquivos de saída.

---

## Instalação

1. Compile `src/AUDEST01.prw` no RPO.
2. Cadastre no menu (SIGAMDI): **Programa** `U_zAudEst`, **Tipo** `Função Protheus`.
3. A pasta `\aud_estrut\relatorio\` é criada automaticamente na 1ª execução.

## Tela

| Campo | Para que serve |
|---|---|
| Produto | Item principal (F3 no SB1). Ao sair do campo, sugere a revisão atual |
| Revisão | Revisão consultada — vale **somente no principal** (`G1_REVINI`/`G1_REVFIM`) |
| Filial | Filial usada em SB1/SG1/SG2. Padrão `00` |
| Nível máximo | Profundidade da explosão e `MAXRECURSION`. Padrão 25 |
| Codificação | ANSI (padrão) ou UTF-8 — ver *Acentuação* abaixo |
| CSV analítico | Uma linha por componente da árvore, para conferir no Excel |
| Árvore completa | Anexa a árvore no fim do HTML (deixa o arquivo pesado) |
| Relatório (servidor) | Onde o arquivo nasce, no AppServer |
| Copiar p/ (estação) | Pasta na máquina do usuário; em branco não copia |

Cada filho é explodido na **revisão atual do cadastro** (`B1_REVATU`), e a
vigência da estrutura usa a data de hoje em `G1_INI` / `G1_FIM`.

## Saída

| Arquivo | Conteúdo |
|---|---|
| `AUDEST_<produto>_<data>_<hora>.html` | Relatório no padrão da engenharia |
| `AUDEST_<produto>_<data>_<hora>.csv` | Árvore completa com as colunas calculadas |

Em UTF-8 o CSV sai com BOM — sem ele o Excel abre o arquivo como ANSI e quebra
a acentuação.

Nas colunas **Estrutura** e **Roteiro** da tabela de erros, `-` significa que a
regra **não se aplica** àquele item — e não que ele passou. É o caso do roteiro
num MP, da estrutura numa folha válida, e das duas num componente que sequer
existe no SB1.

O HTML abre no navegador, imprime em PDF (`Ctrl+P`) e também abre no Word,
preservando cores e tabelas.

Além dos arquivos, o resultado aparece em tela em duas abas — **Erros** e
**Verificar** — para quem não tem acesso à pasta do servidor.

---

## Regras aplicadas

### Folha válida

Encerram o ramo: **MP**, **SV** e os **BN/EM sem estrutura vigente**.
Os demais (PA, PI e BN/EM com estrutura) precisam descer até uma folha válida —
quem não desce é **ERRO de estrutura**.

### Roteiro (SG2, sem filtro de data)

| Tipo | Exige roteiro? |
|---|---|
| PA | Sim, exceto o PA cujo código começa com `FIN` (Finame) |
| PI | Sim |
| EM | Só se tiver estrutura |
| BN | Só se tiver estrutura |
| MP | Não |
| SV | Não |

Tipo que não estiver na tabela é tratado como PA/PI — mesmo comportamento da
query original, cujos `CASE` de MP/SV e BN/EM não pegam tipo desconhecido.

### Quantidade e cadastro

- 15 códigos de chapa: `UM` diferente de `KG` é erro; em `KG`, quantidade acima
  do peso de uma chapa 3000x1200 é erro.
- Qualquer componente com `UM = MM` e quantidade acima de 6000 é erro.
- Ambos são testados **linha a linha** — vale a quantidade daquele componente
  naquele pai, não o acumulado da árvore.

### Pontos a verificar (não são erro)


- Item bloqueado (`B1_MSBLQL = 1`).
- Revisão consultada diferente de `B1_REVATU` — só no item principal.

---

## Manutenção

Três funções no início do fonte concentram o que normalmente muda:

```advpl
AE01Chapas()   // 15 codigos de chapa e o peso de uma chapa 3000x1200
AE01Regras()   // por tipo: quando exige roteiro e quando e folha valida
AE01Criter()   // textos do quadro "CRITERIOS DE ANALISE"
```

`AE01Chapas()` alimenta a classificação (`AE01Class()`); `AE01Regras()` define
também a **ordem das linhas** dos dois quadros do relatório. Os textos de `AE01Regras()` e
`AE01Criter()` vão direto para o HTML, então acentos ali se escrevem como
entidade (`&aacute;`, `&ccedil;`).

Limites gerais ficam nos `#DEFINE` do topo: `AUD_LIMMM` (6000), `AUD_NIVEL` (25),
`AUD_FINAME` (`FIN`), `AUD_FILIAL` (`00`), `AUD_DIRREL`, `AUD_DIRESTA`.

---

## O que ficou no SQL e o que foi para o ADVPL

A query validada pela engenharia está em `AE01Sql()`. Continuam **idênticos** ao
original: a CTE recursiva, o corte de ciclo pelo `Caminho`, o limite de nível, a
vigência (`G1_INI`/`G1_FIM`), a faixa de revisão (`G1_REVINI`/`G1_REVFIM`) e os
`EXISTS` de SG1/SG2.

Três coisas mudaram de lugar, sem mudança de resultado:

| Item | Antes | Agora | Por quê |
|---|---|---|---|
| Nomes físicos | `SB1120` / `SG1120` / `SG2120` | `RetSqlName()` | Roda em qualquer empresa |
| `DECLARE @...` | Duas variáveis | Literais tratados contra apóstrofo | `TCGenQry` envia comando único |
| `TemFilho` | `EXISTS` contra a própria CTE | Calculado em ADVPL | Ver abaixo |
| `Situacao` / `Motivo` | Dois `CASE` no `SELECT` | `AE01Class()` | Manutenção e colunas separadas |

**`TemFilho`.** No original era `EXISTS (SELECT 1 FROM Estrutura F WHERE F.CodPai
= E.Codigo)` — um `EXISTS` correlacionado contra a **própria CTE recursiva**. O
SQL Server não materializa a CTE: ele reexecuta a recursão inteira a cada linha
do resultado. Numa árvore de ~1.700 linhas isso multiplica o custo e inviabiliza
a consulta dentro do SmartClient. Em ADVPL é a mesma informação, obtida de graça:
*este código aparece como pai em alguma linha do retorno*.

**`Situacao` / `Motivo`.** Os dois `CASE` foram transcritos em `AE01Class()`, na
**mesma ordem de avaliação**, com as cláusulas numeradas nos comentários. A ordem
é a regra: quando o componente tem mais de um problema, prevalece a primeira
cláusula que fechar.

Duas consequências dessa ordem, herdadas do original e mantidas de propósito:

- as cláusulas de folha válida (5 e 6) devolvem `OK` **antes** do teste de
  bloqueio (9), então um MP bloqueado sai como `OK`, não como `VERIFICAR`;
- faltando roteiro **e** estrutura, o `Motivo` mostra só `Sem roteiro (SG2)`.

Como o relatório precisa das colunas **Estrutura** e **Roteiro** preenchidas de
forma independente, as duas condições também são avaliadas isoladamente em
`AE01ErrEst()` e `AE01ErrRot()` — é isso que permite marcar `ERRO` nas duas
colunas do mesmo código.

---

## Contagem dos quadros

Os dois quadros contam de formas diferentes, igual ao documento modelo:

- **Análise de estrutura** — por **ocorrência** na árvore. O mesmo código usado
  em dois pais conta duas vezes.
- **Análise de roteiro** — por **código único**. Roteiro é cadastro do item, não
  da posição dele na árvore.

Por isso um mesmo problema aparece como "4 ocorrências" num quadro e "2 códigos"
no cartão de contagem.

Os cartões contam **códigos únicos por natureza de erro**, e o total é a soma das
três naturezas — o mesmo código entra em duas quando lhe falta estrutura e
roteiro ao mesmo tempo.

---

## Acentuação

Todo texto fixo do relatório usa entidade HTML, então sai correto em qualquer
codificação. Só o conteúdo vindo do SB1 (descrição do produto) depende da opção
da tela:

- **ANSI (padrão)** — AppServer com strings em Windows-1252, que é o caso da
  maioria das instalações.
- **UTF-8** — aplica `EncodeUTF8()`. Use quando as descrições saírem com
  caracteres estranhos no ANSI.

---

## Consultas SQL de apoio

Conferir o roteiro de um código:

```sql
SELECT G2_PRODUTO, G2_CODIGO, G2_OPERAC, G2_RECURSO, G2_DESCRI
FROM   SG2120
WHERE  D_E_L_E_T_ = ' '
  AND  G2_FILIAL  = '00'
  AND  G2_PRODUTO = 'EC1REMDIFCHMV0F'
ORDER  BY G2_OPERAC;
```

Conferir a estrutura vigente e a faixa de revisão:

```sql
SELECT G1_COD, G1_COMP, G1_QUANT, G1_REVINI, G1_REVFIM, G1_INI, G1_FIM
FROM   SG1120
WHERE  D_E_L_E_T_ = ' '
  AND  G1_FILIAL  = '00'
  AND  G1_COD     = 'EC1PT00INTBGC4F'
ORDER  BY G1_COMP;
```

Onde um componente é usado (pais diretos):

```sql
SELECT G1_COD, G1_QUANT
FROM   SG1120
WHERE  D_E_L_E_T_ = ' '
  AND  G1_FILIAL  = '00'
  AND  G1_COMP    = 'EC1REMDIFCHMV0F';
```

Cadastro do item, com o que a rotina lê:

```sql
SELECT B1_COD, B1_DESC, B1_TIPO, B1_UM, B1_REVATU, B1_MSBLQL
FROM   SB1120
WHERE  D_E_L_E_T_ = ' '
  AND  B1_FILIAL  = '00'
  AND  B1_COD     = 'FINELVSD08014BA';
```

---

## Desempenho

O custo está na CTE recursiva. Se a explosão ficar lenta, confira os índices de
`SG1` por `G1_FILIAL + G1_COD` e de `SB1` por `B1_FILIAL + B1_COD` — são eles que
sustentam o `INNER JOIN` da recursão e o subselect de `B1_REVATU`.

Reduzir o **nível máximo** também corta custo, mas muda o resultado: um ramo que
não chega à folha dentro do limite passa a ser marcado como erro de estrutura.

Do lado do ADVPL, as buscas por código (o `TemFilho` e o agrupamento por código
único) usam um índice ordenado com busca binária — `AE01Acha()` e `AE01Ins()`.
Com busca linear, uma árvore de 1.700 linhas e ~950 códigos únicos daria cerca
de 3,3 milhões de comparações; pelo índice são ~35 mil.

A lista de códigos pai é montada numa passada à parte, só para os códigos que
têm ocorrência. Um parafuso usado em 800 pais não entra no relatório, e
deduplicar os pais dele custaria caro à toa.
