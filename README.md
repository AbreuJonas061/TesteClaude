# IMPPRD01 — Importação de Produtos no Protheus via ExecAuto

Rotina em **ADVPL** para importar produtos (**SB1** e complemento **SB5**) a partir de
arquivos **CSV** ou **TXT**, utilizando **`MSExecAuto` + `MATA010`**.

A gravação é feita exclusivamente pela rotina automática, portanto **todo produto
importado passa pelas validações nativas do sistema**: `X3_VALID`, gatilhos (SX7),
consistências do cadastro e pontos de entrada.

- Protheus **12.1.2410**
- Compatível com **SmartClient HTML (navegador)** — a tela usa apenas componentes
  suportados no browser e a leitura do arquivo ocorre sempre no lado servidor.

## Conteúdo

| Arquivo | Descrição |
|---|---|
| `src/IMPPRD01.prw` | Fonte completo da rotina (tela + processamento + job) |
| `docs/MANUAL.md` | Manual de instalação, uso, layout e consultas SQL de apoio |
| `exemplos/PRODUTOS_MODELO.csv` | Exemplo com cabeçalho (modo recomendado) |
| `exemplos/PRODUTOS_LAYOUT_FIXO.txt` | Exemplo sem cabeçalho, separado por pipe |

## Instalação rápida

1. Compile `src/IMPPRD01.prw` no RPO.
2. Cadastre no menu (SIGAMDI): **Programa** `U_IMPPRD01`, **Tipo** `Função Protheus`.
3. Crie a pasta `\imp_produtos\` no *rootpath* (a rotina cria automaticamente na 1ª execução).

## Como funciona o mapeamento de campos

O modo padrão usa a **primeira linha do arquivo como cabeçalho**, com os nomes
técnicos dos campos:

```
B1_COD;B1_DESC;B1_TIPO;B1_UM;B1_LOCPAD;B1_PRV1
PA000001;PARAFUSO SEXTAVADO;MP;PC;01;12,50
```

> Para importar um campo novo **não é preciso alterar nem recompilar o fonte** —
> basta acrescentar a coluna no arquivo. A rotina lê o SX3 das tabelas SB1/SB5,
> valida a existência do campo e converte o conteúdo para o tipo correto.

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
- Execução via **Job/Schedule** com `U_IMPPRDJB()`.

Detalhes completos em [`docs/MANUAL.md`](docs/MANUAL.md).
