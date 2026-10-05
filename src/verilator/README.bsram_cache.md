# Two-way BSRAM cache regression

Requires Icarus Verilog (`iverilog` and `vvp`) and Make. From `src`:

```sh
make -C verilator -f Makefile.bsram_cache test
make -C verilator -f Makefile.bsram_cache test SEEDS="7 123" OPS=10000
```

The default runs three deterministic seeds with 4,000 randomized requests each,
plus directed tests. Build output goes to `/tmp/snestang-bsram-cache`;
`BUILD_DIR` overrides that path. An assertion failure returns a nonzero exit
status. The expected-transfer queue holds 262,144 transfers; a 100 ms simulation
watchdog bounds each run. Very large `OPS` settings may need larger limits.

## Organization and replacement

`bsram_cache.v` defaults to `SET_BITS=10`: 1,024 sets, two 16-bit words per set,
2,048 words total (4 KiB). Both ways are read synchronously in parallel on the
front acceptance edge. Each metadata word contains both ways' tags and per-byte
valid/dirty masks, plus one LRU victim bit. A partially valid word owns its tag.

Replacement first chooses a matching tag, then an invalid way (way 0 breaks
an invalid-way tie), then the LRU way. A successful hit or installation makes the
other way LRU. One bit gives exact LRU for two ways. A bypassed inhibited read
does not install data or change LRU.

`front_inhibit[0]` avoids dirty victim eviction on a read miss, preserving the
original inhibit behavior. `front_inhibit[1]` bypasses all cache lookups and
updates: reads and masked byte writes go directly to SDRAM and complete only
after `sd_done`. This fixed exclusion must apply from reset to every alias of
the shared region; changing it while dirty entries exist requires flushing them.
The top latches bit 1 when issuing a request: all non-GSU cartridges bypass the
cache; GSU cartridges bypass BSRAM offsets `0x07C00-0x07FFF` (including the
128 KiB mirrors on Nano), keeping the SNES/RV shared region uncached.

The `clear` input accepts a pulse when a new game starts loading. It blocks new
top-level SNES requests, finishes already queued requests and outstanding
writeback, then reuses the metadata-clear sequence to discard cached entries.
Resident dirty data is discarded, not flushed. Front and SDRAM handshake phases
and the last front response are preserved. The top synchronizes the SNES reset
falling edge into `fclk` and invalidates its tracked BSRAM read result during loading.

The test discovers the number of sets from `$size(dut.meta)` and checks both
data RAM depths. Its geometry calculations and sweeps adapt to power-of-two
capacities up to 16,384 total words (`SET_BITS=13`). Expected data and replacement
decisions use an independent byte memory, two-way tag/mask arrays and LRU model;
no DUT metadata contents are used to predict transfers or victims.

## Coverage

- Cold reads, low/high byte hits, address zero and the final byte of the full
  1 MiB address space; an exhaustive tag sweep at the final set.
- Two conflicting tags coexisting without extra fills, invalid-way preference,
  LRU updates on hits, and third-tag replacement of the correct way.
- Both ways of every set populated, dirtied, evicted and verified against backing
  memory; reset invalidation across both ways of every set.
- Low-only, high-only and both-byte dirty victims from both ways, masked writes,
  partial word allocation and fills that preserve valid dirty bytes.
- Inhibited reads bypass dirty victims without allocation, writeback or LRU
  changes; clean misses and same-tag partial fills still cache. Inhibited write
  misses still allocate and write back their dirty victims.
- Fully uncached repeated reads, masked low/high byte writes visible in backing
  memory at completion, dirty resident preservation, and bypass requests waiting
  for outstanding writeback completion. Both settings of the lower inhibit bit
  are exercised with full bypass enabled.
- Front input changes after acceptance, including the inhibit flag, to verify
  the accepted payload is retained.
- Read fills and write allocations complete before deferred victim writeback.
  Hits and allocations overlap an accepted outstanding write; subsequent fills
  and evictions wait for its completion.
- Queued front requests, reset during unaccepted/accepted incomplete fills and
  writebacks, initialization-held requests and all four ack/done reset phases.
- Clear with both front handshake phases, during a fill and during accepted or
  unaccepted deferred writeback; completion ordering, dirty invalidation, and no
  handshake reset or stale request replay.
- Random hotspots, conflicting tags, repeated and full-range addresses, inhibit
  variation, independent acceptance/completion latencies and early/late read data.
- Every active state, dirty mask, deferred read/write victim mask, inhibit mask,
  both request phases and simultaneous/separate ack/done completion.

After evicting both residents in every set, the test compares the entire backing
memory with the architectural memory, including bytes that must stay untouched.

## Controller interface

`bsram_sdram_model.sv` models toggle phases: `req` toggles for a new request,
`ack` takes that phase on acceptance, and `done` toggles on completion. Payloads
must remain stable until ack. The model retains the accepted payload, allowing
new address/data/control fields to be prepared after ack. The request phase must
remain stable until done, and the cache must not launch another transfer before
completion. Directed overlap tests exercise payload preparation during that wait.

`ds[0]` enables the low byte and `ds[1]` the high byte. Reads fetch an aligned word.
Acceptance/completion delays vary independently. Read data can appear at ack or
only at done; the late-data mode poisons the bus between transfers to detect
premature sampling. Every issued transfer is checked for ordering, address,
direction, masks and enabled writeback bytes.

The cache accepts in `IDLE`, processes synchronous RAM outputs in `LOOKUP`, and
launches read misses directly into `WAIT_FILL`. The victim remains in the read
registers while replacement updates the RAMs. `WRITEBACK` copies it to the backend
registers before returning to IDLE; `write_waiting` guards subsequent transfers
until done. The test checks completion-time front data; the cache also exposes
SDRAM data directly while waiting for a fill.
Fully uncached transfers also use `LOOKUP`, `WAIT_FILL`, and `RESPOND`, without
allocating or evicting entries; bypass writes retain the accepted byte output.

This models the cache/controller boundary. It does not verify production SDRAM
pins, arbitration, refresh, clock-domain crossings, or implementation timing.
