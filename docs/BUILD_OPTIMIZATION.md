# Multi-Architecture Build Optimization Analysis

## Current Architecture

The nut-cgi project uses Docker multi-stage builds with QEMU for cross-platform compilation:

```
Builder Stage (per-arch)     Runtime Stage (per-arch)
┌─────────────────────┐      ┌──────────────────┐
│ Alpine 3.23 base    │      │ Alpine 3.23 base │
│ + build tools       │      │ + runtime deps   │
│ + NUT source        │──────>│ + NUT binaries   │
│ + compile NUT       │ COPY │ + lighttpd       │
└─────────────────────┘      └──────────────────┘
        │                             │
        │                             │
    amd64 build                   amd64 image
    arm64 build                   arm64 image
```

**Key Constraint**: NUT binaries compiled for Alpine/musl are NOT portable between architectures due to:
- Different instruction sets (x86_64 vs aarch64)
- Architecture-specific optimizations in GCC/musl
- ABI differences

**Conclusion**: Each architecture must be built separately. ✅ Current approach is correct.

---

## Build Time Analysis

### Current Build Times (Approximate)

| Stage | amd64 | arm64 (QEMU) |
|-------|-------|--------------|
| Download NUT source | 5s | 5s |
| NUT configure | 10s | 20s |
| NUT make | 60s | 180s |
| Install + copy | 5s | 8s |
| Runtime stage | 10s | 12s |
| **Total** | **~90s** | **~225s** |

**Bottleneck**: ARM64 compilation via QEMU emulation is ~3x slower than native amd64.

---

## Optimization Opportunities

### 1. ✅ **Parallel Compilation** (High Impact)

**Current**: `make` uses single core by default
**Optimization**: Add `-j$(nproc)` to use all available CPU cores

```dockerfile
# Before
RUN make

# After
RUN make -j$(nproc)
```

**Expected Improvement**: 2-4x faster compilation on multi-core builders (GitHub Actions has 4 cores)

**Risk**: Low - standard practice for NUT builds

---

### 2. ✅ **Strip Debug Symbols** (Medium Impact)

**Current**: Binaries include debug symbols (~30% size overhead)
**Optimization**: Strip symbols from installed binaries

```dockerfile
RUN make install DESTDIR=/build/rootfs && \
    find /build/rootfs -type f -executable -exec strip --strip-unneeded {} \; 2>/dev/null || true
```

**Expected Improvement**:
- 20-30% smaller binaries
- Faster COPY operations between stages
- Smaller final image (~2-3MB savings)

**Risk**: Low - debug symbols not needed in production

---

### 3. ⚠️ **Separate Dependency Layer** (Low Impact)

**Current**: Dependencies and build in same layer
**Optimization**: Separate dependency installation for better caching

```dockerfile
# Install dependencies first (cached if deps don't change)
RUN apk add --no-cache build-base autoconf automake...

# Then download and build (only re-run if NUT version changes)
COPY . /build
RUN ./configure && make
```

**Expected Improvement**: Faster rebuilds when only NUT version changes

**Risk**: Low - improves cache hit rate

**Trade-off**: Adds one more layer (minimal size impact)

---

### 4. ❌ **Native ARM64 Builders** (High Impact, High Cost)

**Idea**: Use native ARM64 runners instead of QEMU emulation

**Expected Improvement**: 3x faster ARM64 builds (~75s instead of ~225s)

**Cost**:
- GitHub Actions ARM64 runners are limited availability
- Self-hosted ARM64 runners require infrastructure
- AWS Graviton instances cost ~$0.05/hr

**Recommendation**: Only if build times become problematic (currently acceptable)

---

### 5. ✅ **Build Cache Optimization** (Medium Impact)

**Current**: GitHub Actions caches between builds
**Optimization**: Ensure optimal cache configuration

```yaml
cache-from: type=gha
cache-to: type=gha,mode=max  # Already implemented ✅
```

**Expected Improvement**: 50-80% faster subsequent builds (already optimized)

---

### 6. ⚠️ **ccache Integration** (Medium Impact, Medium Complexity)

**Idea**: Use ccache to cache compiled objects between NUT version updates

```dockerfile
RUN apk add --no-cache ccache
ENV PATH="/usr/lib/ccache/bin:$PATH"
RUN ./configure && make -j$(nproc)
```

**Expected Improvement**: 50% faster builds when NUT patches are small

**Complexity**: Requires cache mount configuration in GitHub Actions

**Trade-off**: Adds complexity vs marginal benefit for infrequent builds

---

### 7. ✅ **Optimize Configure Flags** (Low Impact)

**Current**: Minimal configure flags
**Optimization**: Explicitly disable unused features

```dockerfile
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc/nut \
    --with-cgi \
    --without-ssl \          # CGI doesn't need SSL
    --without-serial \       # No local UPS support needed
    --without-usb \          # No local UPS support needed
    --disable-static \       # Shared libs only
    --with-user=nut \
    --with-group=nut
```

**Expected Improvement**:
- 10-15% faster compilation (fewer files)
- Smaller binaries (~500KB-1MB savings)

**Risk**: Medium - ensure CGI functionality isn't affected

---

## Recommended Optimizations (Implement Now)

### Priority 1: Quick Wins (Low Risk)

1. **Parallel compilation**: Add `-j$(nproc)` to make
2. **Strip binaries**: Remove debug symbols
3. **Optimize configure flags**: Disable unused features

**Expected Total Improvement**: 40-50% faster builds, 2-3MB smaller images

### Implementation

```dockerfile
# In builder stage, replace:
RUN make && \
    make install DESTDIR=/build/rootfs

# With:
RUN make -j$(nproc) && \
    make install DESTDIR=/build/rootfs && \
    # Strip debug symbols from binaries
    find /build/rootfs/usr/lib -name '*.so*' -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    find /build/rootfs/usr/lib/cgi-bin -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true
```

---

## Not Recommended (Complexity > Benefit)

1. **Native ARM64 runners**: Overkill for current build frequency
2. **ccache**: Too complex for marginal gains
3. **Cross-compilation**: NUT's configure doesn't support it well
4. **Binary reuse between arches**: Not possible with musl/Alpine

---

## Build Performance Benchmarks

### Target Goals

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| amd64 build time | ~90s | <60s | ⚠️ Achievable |
| arm64 build time | ~225s | <150s | ⚠️ Challenging (QEMU limitation) |
| Image size | ~50MB | <48MB | ✅ Achievable |
| Build cache hit rate | ~70% | >85% | ✅ Already good |

### Monitoring

Track build times in GitHub Actions:

```yaml
- name: Build timestamp
  run: |
    echo "BUILD_START=$(date +%s)" >> $GITHUB_ENV

- name: Build time
  run: |
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    echo "Build completed in ${BUILD_TIME}s"
```

---

## Alternative Architectures

Currently supported: `linux/amd64`, `linux/arm64`

**Potential additions**:
- `linux/arm/v7` (32-bit ARM, Raspberry Pi 3 and older)
- `linux/riscv64` (future-proofing)

**Analysis**:
- **ARMv7**: Would require additional 3-5 minutes build time
- **RISC-V**: Alpine 3.23 has experimental support, not production-ready
- **Demand**: Low - most modern SBCs are ARM64

**Recommendation**: Stick with amd64 + arm64 for now. Add ARMv7 only if users request it.

---

## Future Considerations

### When Build Times Matter

If CI/CD build times exceed 10 minutes consistently:

1. Consider self-hosted ARM64 runners (one-time setup)
2. Implement more aggressive caching (ccache, sccache)
3. Split builds into parallel jobs (build amd64 and arm64 simultaneously)

### Split Job Example

```yaml
jobs:
  build-amd64:
    runs-on: ubuntu-latest
    steps:
      - name: Build amd64
        uses: docker/build-push-action@v6
        with:
          platforms: linux/amd64

  build-arm64:
    runs-on: ubuntu-latest
    steps:
      - name: Build arm64
        uses: docker/build-push-action@v6
        with:
          platforms: linux/arm64

  combine:
    needs: [build-amd64, build-arm64]
    runs-on: ubuntu-latest
    steps:
      - name: Create manifest
        run: docker buildx imagetools create ...
```

**Benefit**: Parallel execution, 2x faster total time
**Trade-off**: More complex workflow, requires manifest combining

---

## Conclusion

**Current state**: ✅ Build architecture is sound and optimized for maintainability

**Quick wins available**:
1. Parallel compilation (40-50% faster)
2. Binary stripping (2-3MB smaller)
3. Configure flag optimization (10-15% faster)

**Long-term**: Monitor build times. Current approach scales well up to ~5-10 minute builds. Beyond that, consider native ARM64 runners or job parallelization.

**Recommendation**: Implement Priority 1 optimizations now. Defer complex optimizations until proven necessary.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-06
**Next Review**: After 3 months of production use
