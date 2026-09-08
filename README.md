# Rotinas ADVPL — Protheus 12.1.2410

| Rotina | Menu | O que faz |
|---|---|---|
| [`zImpPro`](#zimppro--importação-de-produtos-via-execauto) | `U_zImpPro` | Importa produtos (SB1/SB5) de CSV/TXT via `MSExecAuto` + `MATA010` |
| [`zAudEst`](#zaudest--auditoria-de-roteiro--estrutura) | `U_zAudEst` | Audita estrutura (SG1) e roteiro (SG2) de toda a árvore de um item |

---

# zImpPro — Importação de Produtos via ExecAuto

Rotina em **ADVPL** para importar produtos (**SB1** e complemento **SB5**) a partir de
arquivos **CSV** ou **TXT**, utilizando **`MSExecAuto` + `MATA010`**.

A gravação é feita exclusivamente pela rotina automática, portanto **todo produto
importado passa pelas validações nativas do sistema**: `X3_VALID`, gatilhos (SX7),
consistências do cadastro e pontos de entrada.

- Protheus **12.1.2410**
- Compatível com **SmartClient HTML (navegador)** — a tela usa apenas componentes
  suportados no browser. O arquivo é sempre selecionado na **máquina local** de
  quem está usando o sistema; o próprio `cGetFile()` faz o upload para o servidor,
  onde ocorre toda a leitura e o processamento.

## Conteúdo

| Arquivo | Descrição |
|---|---|
| `src/IMPPRD01.prw` | Fonte completo da rotina (tela + processamento) |
| `docs/MANUAL.md` | Manual de instalação, uso, layout e consultas SQL de apoio |
| `exemplos/PRODUTOS_MODELO.csv` | Exemplo com cabeçalho (modo recomendado) |
| `exemplos/PRODUTOS_LAYOUT_FIXO.txt` | Exemplo sem cabeçalho, separado por pipe |

## Instalação rápida

1. Compile `src/IMPPRD01.prw` no RPO.
2. Cadastre no menu (SIGAMDI): **Programa** `U_zImpPro`, **Tipo** `Função Protheus`.
3. Crie a pasta `\imp_produtos\` no *rootpath* (a rotina cria automaticamente na 1ª execução).

## Como funciona o mapeamento de campos

O modo padrão usa a **primeira linha do arquivo como cabeçalho**, com os nomes
técnicos dos campos:

```
B1_COD;B1_DESC;B1_TIPO;B1_UM;B1_SEGUM;B1_LOCPAD;B1_PRV1;B1_CONTA
PA000001;PARAFUSO SEXTAVADO;MP;PC;PC;01;12,50;11010001
```

> Para importar um campo novo **não é preciso alterar nem recompilar o fonte** —
> basta acrescentar a coluna no arquivo. A rotina lê o SX3 das tabelas SB1/SB5,
> valida a existência do campo e converte o conteúdo para o tipo correto.

`B1_SEGUM` (segunda unidade de medida) e `B1_CONTA` (conta contábil) costumam ser
obrigatórios no dicionário — sem eles o ExecAuto rejeita todos os registros.

Também é aceito o **título do dicionário** no lugar do nome técnico
(`Descricao` em vez de `B1_DESC`), e existe o modo de **layout fixo** (sem
cabeçalho) configurado na função `IP01Layout()`.

## Recursos

- Inclusão (`nOpc 3`) e alteração (`nOpc 4`) decididas automaticamente pela
  existência do `B1_COD` no SB1.
- Erro capturado com `GetAutoGRLog()` — **não abre `MostraErro`**, por isso a carga
  em lote nunca trava esperando interação.
- Transação por registro: uma linha com erro não derruba as demais.
- Detecção automática de separador (`;`, `|`, TAB, `,`).
- Parser CSV que respeita aspas — `"CABO 2,5MM; AZUL"` não é quebrado indevidamente.
- Conversão numérica nos formatos brasileiro (`1.234,56`) e americano (`1234.56`).
- Tratamento de codificação UTF-8 / ANSI e remoção de BOM.
- Rejeição de códigos duplicados dentro do próprio arquivo.
- **Modo simulação**: valida o arquivo inteiro sem gravar nada.
- Log em arquivo + **CSV de rejeitados com o motivo**, pronto para corrigir e reimportar.

Detalhes completos em [`docs/MANUAL.md`](docs/MANUAL.md).

---

# zAudEst — Auditoria de Roteiro / Estrutura

Rotina em **ADVPL** que explode a estrutura de um item (**SG1**), confere o roteiro
(**SG2**) e o cadastro (**SB1**) em toda a árvore e gera um relatório no padrão de
auditoria usado pela engenharia.

**Somente leitura** — não faz `INSERT`, `UPDATE` nem `DELETE`. O único efeito é a
criação dos arquivos de saída.

- Requer **SQL Server**: a explosão usa CTE recursiva.
- Saída: **HTML** (abre no navegador, imprime em PDF, abre no Word) e, opcionalmente,
  um **CSV analítico** com a árvore inteira.
- O resultado também aparece em tela, em abas de *Erros* e *Verificar*, para quem
  não tem acesso à pasta do servidor.

## O que ele aponta

| Natureza | Regra |
|---|---|
| Estrutura | PA/PI (e BN/EM com estrutura) precisam descer até uma folha válida — MP, SV ou BN/EM sem estrutura |
| Roteiro | PA/PI sempre exigem SG2, exceto o PA `FIN*` (Finame); EM/BN só se tiverem estrutura; MP/SV não exigem |
| Quantidade | 15 códigos de chapa exigem `UM = KG` e quantidade até o peso de uma chapa 3000x1200; `UM = MM` acima de 6000 é erro |
| Verificar | Item bloqueado, e revisão consultada diferente de `B1_REVATU` no item principal |

## Instalação rápida

1. Compile `src/AUDEST01.prw` no RPO.
2. Cadastre no menu (SIGAMDI): **Programa** `U_zAudEst`, **Tipo** `Função Protheus`.
3. A pasta `\aud_estrut\relatorio\` é criada na 1ª execução.

## Manutenção

Três funções no início do fonte concentram o que normalmente muda — a lista de
chapas com teto, a regra de roteiro/folha por tipo e os textos dos critérios:

```advpl
AE01Chapas()   // 15 codigos de chapa e o peso de uma chapa 3000x1200
AE01Regras()   // por tipo: quando exige roteiro e quando e folha valida
AE01Criter()   // textos do quadro "CRITERIOS DE ANALISE"
```

Detalhes completos — incluindo o mapa do que ficou no SQL e o que foi para o
ADVPL — em [`docs/MANUAL_AUDEST.md`](docs/MANUAL_AUDEST.md).
