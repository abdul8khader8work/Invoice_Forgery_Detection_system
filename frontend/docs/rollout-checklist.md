# Rollout Checklist for New Scan UI

## Phase: QA (Internal Testing)

### Pre-Rollout Requirements
- [ ] All unit tests pass (`flutter test`)
- [ ] All widget tests pass (`flutter test`)
- [ ] Integration tests pass (`flutter test integration_test/`)
- [ ] Flutter analyze passes with zero errors in new files (`flutter analyze lib/`)
- [ ] Web build successful with WASM (`flutter build web --web-renderer wasm`)
- [ ] Windows build successful (`flutter build windows`)
- [ ] Android build successful (`flutter build apk`)
- [ ] iOS build successful (macOS only, `flutter build ios`)

### Cross-Platform Testing
- [ ] **Web (Chrome with WASM)**
  - [ ] Drag/drop works
  - [ ] Gallery picker works
  - [ ] File picker works
  - [ ] Keyboard navigation works (Tab/Enter/Space)
  - [ ] Touch targets accessible
  - [ ] Animations respect accessibleNavigation
  - [ ] Load time < 2s on 4G

- [ ] **Windows Desktop**
  - [ ] File picker works
  - [ ] Keyboard navigation works
  - [ ] Window resizing works correctly
  - [ ] Touch targets accessible
  - [ ] Camera button hidden (platform-specific)

- [ ] **Android**
  - [ ] Camera works
  - [ ] Gallery works
  - [ ] File picker works
  - [ ] Touch targets accessible (48px minimum)
  - [ ] Animations smooth
  - [ ] Back button navigation works

- [ ] **iOS** (if available)
  - [ ] Camera works
  - [ ] Gallery works
  - [ ] File picker works
  - [ ] Touch targets accessible
  - [ ] Animations smooth
  - [ ] Swipe back navigation works

### Feature Flag Testing
- [ ] Default behavior: old UI shown
- [ ] With `--dart-define=ENABLE_NEW_SCAN_UI=true`: new UI shown
- [ ] Deep link `/new-scan` works only when flag enabled
- [ ] Deep link `/scan` works regardless of flag
- [ ] Debug overlay shows correct flag state
- [ ] Flag toggle doesn't require app restart (via debug overlay)

### Grok Fallback Testing
- [ ] Grok API timeout triggers fallback banner
- [ ] Grok API rate limit triggers fallback banner
- [ ] Fallback shows rule-based results
- [ ] App doesn't crash on Grok failure
- [ ] Retry button works after Grok failure

### Performance Testing
- [ ] Image preprocessing works (resize to 1920px, JPEG 85%)
- [ ] Upload progress indicator shows correctly
- [ ] Processing steps show in sequence
- [ ] Skeleton loaders show during async states
- [ ] Memory usage stable on 8GB RAM system
- [ ] No memory leaks during repeated scans

### Accessibility Testing
- [ ] Screen reader announces all interactive elements
- [ ] All buttons have minimum 48x44 touch targets
- [ ] Keyboard navigation works (Tab/Enter/Space/Escape)
- [ ] Color contrast ratios meet WCAG AA
- [ ] Animations disabled when accessibleNavigation is true
- [ ] Semantics labels present on all interactive elements

---

## Phase: Internal Rollout (Team Testing)

### Rollout Commands
```bash
# Enable new UI for internal testing
flutter run --dart-define=ENABLE_NEW_SCAN_UI=true

# Or edit .env file:
ENABLE_NEW_SCAN_UI=true
```

### Internal Testing Checklist
- [ ] Team members test new scan flow
- [ ] Feedback collected on UX
- [ ] Bug reports documented
- [ ] Performance metrics collected
- [ ] Telemetry data reviewed
- [ ] Grok fallback scenarios tested
- [ ] Edge cases tested (large files, corrupted files, etc.)

### Go/No-Go Criteria
- **Go**: Zero critical bugs, performance acceptable, positive UX feedback
- **No-Go**: Critical bugs present, performance issues, negative UX feedback

---

## Phase: 10% Traffic Rollout

### Rollout Strategy
- Feature flag enabled for 10% of users
- Monitor metrics closely
- Roll back if issues detected

### Monitoring Metrics
- [ ] Scan success rate > 95%
- [ ] Average scan time < 30 seconds
- [ ] Grok fallback rate < 5%
- [ ] App crash rate < 0.1%
- [ ] API error rate < 2%
- [ ] User satisfaction score > 4/5

### Rollback Triggers
- Crash rate > 1%
- Scan success rate < 90%
- Average scan time > 60 seconds
- User complaints > 5 per day

---

## Phase: 50% Traffic Rollout

### Rollout Strategy
- Feature flag enabled for 50% of users
- Continue monitoring metrics
- Prepare for full rollout

### Monitoring Metrics
- [ ] Scan success rate > 95%
- [ ] Average scan time < 30 seconds
- [ ] Grok fallback rate < 5%
- [ ] App crash rate < 0.1%
- [ ] API error rate < 2%
- [ ] User satisfaction score > 4/5

### Rollback Triggers
- Same as 10% rollout

---

## Phase: 100% Traffic Rollout

### Rollout Strategy
- Feature flag enabled for all users
- Full monitoring in place
- Deprecate old UI

### Deprecation Timeline
- **Week 1**: 100% new UI
- **Week 2**: Remove old UI code (if stable)
- **Week 3**: Clean up feature flags
- **Week 4**: Remove old UI routes

### Final Checklist
- [ ] All monitoring metrics stable for 7 days
- [ ] Zero critical bugs reported
- [ ] User feedback positive
- [ ] Performance within acceptable range
- [ ] Old UI code removed
- [ ] Feature flags cleaned up
- [ ] Documentation updated

---

## Post-Rollout

### Success Criteria
- [ ] New UI adopted by all users
- [ ] Old UI fully deprecated
- [ ] Performance metrics stable
- [ ] User satisfaction maintained
- [ ] Codebase simplified (no duplicate UI)

### Lessons Learned
- Document what worked well
- Document what could be improved
- Update development practices
- Update onboarding documentation
