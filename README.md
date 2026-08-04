# MT5 to MT4 Bridge (ZeroMQ RAM Protocol)

Sincronização de sinais de trading de alta frequência e ultra-baixa latência entre os terminais **MetaTrader 5** e **MetaTrader 4 (Conta Cent/Padrão)** utilizando comunicação direta em memória via **Sockets TCP Locais (ZeroMQ)**.

---

## 🚀 Visão Geral da Arquitetura

Esta versão da ponte elimina completamente o gargalo de **File I/O (I/O de Disco)**. Toda a inteligência da estratégia, execução do modelo Keras V4 e decisões do Trailing Stop permanecem concentradas no motor **Python no MT5**. 

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

## 🛠️ Requisitos de Sistema & Pré-requisito C++ (32-bit)

> [!IMPORTANT]
> O MetaTrader 4 é uma aplicação **32-bits (x86)**. A DLL do ZeroMQ em 32-bits (`libzmq.dll`) necessita do **Microsoft Visual C++ 2015-2022 Redistributable (x86)** instalado no Windows (`msvcp140.dll` e `vcruntime140.dll`).
>
> Se o MT4 apresentar o erro `Cannot load '...\libzmq.dll' [193]` (ERROR_BAD_EXE_FORMAT), significa que o runtime 32-bits do C++ não está instalado no sistema Windows.

### Como baixar e instalar o `vc_redist.x86.exe`:

* **Link Direto de Download (Microsoft)**: [vc_redist.x86.exe](https://aka.ms/vs/17/release/vc_redist.x86.exe)

* **Download e Instalação Silenciosa via PowerShell**:
  ```powershell
  Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x86.exe' -OutFile 'vc_redist.x86.exe'
  Start-Process -FilePath '.\vc_redist.x86.exe' -ArgumentList '/quiet /norestart' -Wait
  ```

*(Nota: O instalador `vc_redist.x86.exe` é um binário de sistema e está ignorado no `.gitignore` para não ser versionado no Git).*

---

## 📂 Instruções de Instalação e Distribuição dos Arquivos

Para a ponte ZeroMQ funcionar na prática, copie as DLLs e bibliotecas de *Include* para as pastas de dados de cada terminal:

### 1. No MetaTrader 5 (Emissor / Publisher)

Abra o MT5 $\rightarrow$ `Arquivo` $\rightarrow$ `Abrir Pasta de Dados` $\rightarrow$ entre em `MQL5`:

* **`SignalSenderEA_MT5.mq5`** $\rightarrow$ Cole em `MQL5/Experts/`
* **Pastas da diretório `Include/`** (`Zmq` e `Mql`) $\rightarrow$ Cole em `MQL5/Include/`
* **`libzmq.dll` e `libsodium.dll`** (da pasta `Library/MT5/`) $\rightarrow$ Cole em `MQL5/Libraries/`

### 2. No MetaTrader 4 (Receptor Cent / Subscriber)

Abra o MT4 $\rightarrow$ `Arquivo` $\rightarrow$ `Abrir Pasta de Dados` $\rightarrow$ entre em `MQL4`:

* **`SignalReceiverEA_MT4.mq4`** $\rightarrow$ Cole em `MQL4/Experts/`
* **Pastas do diretório `Include/`** (`Zmq` e `Mql`) $\rightarrow$ Cole em `MQL4/Include/`
* **`libzmq.dll`, `libsodium.dll`, `msvcp140.dll` e `vcruntime140.dll`** (da pasta `Library/MT4/`) $\rightarrow$ Cole em `MQL4/Libraries/`

---

## ⚙️ Configuração OBRIGATÓRIA nos Terminais

Em **ambos** os terminais (MT4 e MT5), vá em **`Ferramentas` $\rightarrow$ `Opções` $\rightarrow$ `Experts`**:

* ✅ Marque **Permitir negociação automatizada** (*Algo Trading*)
* ✅ Marque **Permitir importação de DLLs** *(Essencial para carregar a `libzmq.dll`)*

---

## ⚙️ Parâmetros dos EAs

### SignalSenderEA_MT5 (Emissor)
* `InpZmqHost`: `"127.0.0.1"` (Host local)
* `InpZmqPort`: `5555` (Porta TCP local)
* `InpMagicNumber`: `40000100` (Filtro por Magic Number)

### SignalReceiverEA_MT4 (Receptor)
* `InpZmqHost`: `"127.0.0.1"`
* `InpZmqPort`: `5555`
* `InpSymbolSuffix`: `"m"` ou `"c"` (Ajuste do sufixo da corretora, ex: `EURUSD` $\rightarrow$ `EURUSDm`)
* `InpMagicNumber`: `40000100`
* `InpSlippage`: `3`
* `InpTimerInterval`: `10` (Intervalo de polling em milissegundos)

---

## 🛠️ Especificação do Protocolo JSON (ZeroMQ Payload)

As mensagens trafegadas no socket seguem o formato atômico em JSON:

### 1. Ordem Individual (BUY / SELL)
```json
{
  "action": "OPEN",
  "type": "BUY",
  "symbol": "EURUSD",
  "lot": 0.01,
  "magic": 40000100,
  "mt5_ticket": 1942764004,
  "timestamp": 1785812101
}
```

### 2. Fechamento Específico (TP Isolado)
```json
{
  "action": "CLOSE_TICKET",
  "symbol": "EURUSD",
  "magic": 40000100,
  "mt5_ticket": 1942764004,
  "timestamp": 1785812200
}
```

### 3. Liquidação Global do Ciclo (Trailing Stop Trigger)
```json
{
  "action": "CLOSE_ALL",
  "symbol": "EURUSD",
  "magic": 40000100,
  "timestamp": 1785812250
}
```

---

## 📋 Componentes do Repositório

* **`SignalSenderEA_MT5.mq5` (ZeroMQ Publisher):** Intercepta novos *deals* e eventos de negociação no MT5 e publica as mensagens no socket `5555`.
* **`SignalReceiverEA_MT4.mq4` (ZeroMQ Subscriber):** Fica escutando ativamente a porta `5555` em *non-blocking mode*, ajusta o sufixo da corretora e dispara as ordens a mercado.
* **`Include/Zmq/` & `Include/Mql/`:** Bibliotecas de bindings MQL4/MQL5 para ZeroMQ.
* **`Library/MT4/`:** Binários DLL de **32-bits (x86)** (`libzmq.dll` e `libsodium.dll`).
* **`Library/MT5/`:** Binários DLL de **64-bits (x64)** (`libzmq.dll` e `libsodium.dll`).
