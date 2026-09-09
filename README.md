# zImpPro — Importação de Produtos no Protheus via ExecAuto

Rotina em **ADVPL** para importar produtos (**SB1** e complemento **SB5**) a partir de
arquivos **CSV** ou **TXT**, usando **`MSExecAuto` + `MATA010`**.

A gravação é feita exclusivamente pela rotina automática, então **todo produto passa
pelas validações nativas do sistema**: `X3_VALID`, gatilhos (SX7), consistências do
cadastro e pontos de entrada.

- Protheus **12.1.2410**
- Compatível com **SmartClient HTML (navegador)**

## Como usar

1. Clique em `...` e escolha o arquivo na sua máquina.
2. Deixe **"Somente simular"** marcado e clique em **Importar** para conferir.
3. Corrija o que a tela apontar e rode de novo, agora sem simular.

Só isso. Separador (`;`, `|`, TAB, `,`) e codificação (UTF-8 ou ANSI) são
detectados automaticamente.

## O arquivo

A primeira linha traz os **nomes técnicos dos campos**, em qualquer ordem:

```
B1_COD;B1_DESC;B1_TIPO;B1_UM;B1_SEGUM;B1_LOCPAD;B1_PRV1;B1_CONTA;B5_CEME
PA000001;PARAFUSO SEXTAVADO;MP;PC;PC;01;12,50;11010001;9092026
```

Campos do complemento (**`B5_*`**) entram no mesmo arquivo, junto dos `B1_*` —
o `MATA010` grava as duas tabelas de uma vez. Não é preciso um segundo ExecAuto.

- Para importar um campo novo, **acrescente a coluna** — sem recompilar o fonte.
- `B1_COD` é o único obrigatório para a rotina; o resto quem exige é o dicionário.
- Coluna que não existe no dicionário é **ignorada** e listada no resumo (não trava
  a importação).
- `B1_SEGUM` e `B1_CONTA` costumam ser obrigatórios — sem eles o ExecAuto rejeita.

## Quando dá erro

A tela de resultado lista **linha, produto e o que aconteceu**, já em linguagem
direta:

```
Linha  Produto      O que aconteceu
2      PA000001     B1_SEGUM: O campo Seg.Un.Medi. nao foi preenchido
5      PA000004     Este codigo pertence a um produto EXCLUIDO (registro 148828)
```

O log completo fica em `\imp_produtos\log\` no servidor e é copiado para
`C:\Erros Protheus` na máquina do usuário.

## Instalação

1. Compile `src/IMPPRD01.prw` no RPO.
2. Cadastre no menu (SIGAMDI): **Programa** `U_zImpPro`, **Tipo** `Função Protheus`.

## Manutenção

`IP01Fixos()`, no início do fonte, é o único ponto que normalmente se altera —
valores aplicados a todos os produtos quando a coluna não vem no arquivo:

```advpl
Static Function IP01Fixos()
    Local aFix := {}
    aAdd(aFix, {"B1_MSBLQL", "2"})    // produto liberado
    // aAdd(aFix, {"B1_SEGUM" , "UN"})
Return aFix
```

Detalhes em [`docs/MANUAL.md`](docs/MANUAL.md).
