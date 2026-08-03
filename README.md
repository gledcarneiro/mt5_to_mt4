# MT5 to MT4 Bridge (ZeroMQ RAM Protocol)

Sincronização de sinais de trading de alta frequência e ultra-baixa latência entre os terminais **MetaTrader 5** e **MetaTrader 4 (Conta Cent/Padrão)** utilizando comunicação direta em memória via **Sockets TCP Locais (ZeroMQ)**.

---

## 🚀 Visão Geral da Arquitetura

Esta nova versão da ponte elimina completamente o gargalo de **File I/O (I/O de Disco)**. Toda a inteligência da estratégia, execução do modelo Keras V4 e decisões do Trailing Stop permanecem concentradas no motor **Python no MT5**. 

O **MT4** atua como um executor passivo de ordens a mercado na conta Cent, recebendo instruções em tempo real via **RAM Sockets** sem concorrência de arquivos no sistema.


```

+------------------------+          +--------------------------+          +--------------------------+
|  V4 Python Engine      |  MQL5    |  SignalSenderEA (MT5)    |  ZeroMQ  |  SignalReceiverEA (MT4)  |
|  (Keras V4 + Dynamic)  | -------->|  ZeroMQ Publisher (PUB)  | -------->|  ZeroMQ Subscriber (SUB) |
|  - MT5 Execution       |          |  tcp://127.0.0.1:5555    |   RAM    |  - Cent Account Execution|
+------------------------+          +--------------------------+          +--------------------------+

```

---

## ⚡ Principais Evoluções (V4 ZeroMQ vs. File I/O)

* **Ultra-baixa Latência:** Redução do tempo de repasse de sinais de ~100ms (disco) para **1ms a 3ms (RAM)**.
* **Sem Trava de Arquivos:** Eliminação total de erros de concorrência (`ERR_FILE_CANNOT_OPEN`).
* **Liquidação Massiva Otimizada (Close All):** Em disparos do Trailing Stop com múltiplas posições abertas, o MT5 emite um único pacote atômico de liquidação em vez de centenas de operações individuais.
* **Isolamento de Estado:** A MQL4 no MT4 não precisa recalcular regras complexas de gestão de risco; apenas executa espelhamento estrito.

---

## 🛠️ Especificação do Protocolo JSON (ZeroMQ Payload)

As mensagens trafegadas no socket seguem o formato atômico em JSON:

### 1. Ordem Individual (BUY / SELL)
```json
{
  "action": "OPEN",
  "type": "BUY",
  "symbol": "EURUSD",
  "lot": 0.10,
  "magic": 40000100,
  "mt5_ticket": 1939535398,
  "timestamp": 1785708483
}

```

### 2. Fechamento Específico (TP Isolado)

```json
{
  "action": "CLOSE_TICKET",
  "symbol": "EURUSD",
  "magic": 40000100,
  "mt5_ticket": 1939535398,
  "timestamp": 1785708500
}

```

### 3. Liquidação Global do Ciclo (Trailing Stop Trigger)

```json
{
  "action": "CLOSE_ALL",
  "symbol": "EURUSD",
  "magic": 40000100,
  "timestamp": 1785708520
}

```

---

## 📋 Componentes do Repositório

* **`SignalSenderEA_MT5.mq5` (ZeroMQ Publisher):** Intercepta novos *deals* e eventos de negociação no MT5 e publica as mensagens no socket `5555`.
* **`SignalReceiverEA_MT4.mq4` (ZeroMQ Subscriber):** Fica escutando ativamente a porta `5555` em *non-blocking mode*, ajusta o sufixo da corretora (ex: `EURUSD` -> `EURUSDc`) e dispara as ordens a mercado.
* **`libzmq.dll` / `mql-zmq`:** Bibliotecas de vínculo dinâmico para suporte a Sockets nativos no MQL4/MQL5.

---

## ⚙️ Configuração dos EAs

### SignalSenderEA_MT5 (Emissor)

* `InpZmqPort`: `5555` (Porta TCP local)
* `InpMagicNumber`: `40000100` (Filtro do robô V4)

### SignalReceiverEA_MT4 (Receptor Cent)

* `InpZmqHost`: `"127.0.0.1"`
* `InpZmqPort`: `5555`
* `InpSymbolSuffix`: `"c"` (Exemplo para contas Cent: `EURUSDc`)
* `InpMagicNumber`: `40000100`

```

```
