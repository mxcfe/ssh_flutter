import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_flutter/services/session_layout.dart';
import 'package:ssh_flutter/services/ssh_session.dart';

void main() {
  late int seq;
  late SessionLayout layout;

  setUp(() {
    seq = 0;
    layout = SessionLayout(newId: () => 'id${seq++}');
  });

  tearDown(() {
    for (final tab in layout.tabs.values) {
      tab.session.dispose();
    }
  });

  test('each connection opens in its own window', () {
    final a = SshSession();
    final b = SshSession();
    final first = layout.addWindow(a);
    final second = layout.addWindow(b);

    expect(layout.windows, hasLength(2));
    expect(identical(layout.tabs[first.activeTabId]!.session, a), isTrue);
    expect(identical(layout.tabs[second.activeTabId]!.session, b), isTrue);
  });

  test('move one tab into another window and drop the empty source', () {
    final source = layout.addWindow(SshSession());
    final target = layout.addWindow(SshSession());
    final moved = layout.tabs[source.activeTabId]!.session;

    final removed = layout.moveTabTo(source.activeTabId, target.id);

    expect(removed, source.id);
    expect(layout.find(source.id), isNull);
    expect(target.tabIds, hasLength(2));
    expect(target.activeTabId, isNot(target.tabIds.first));
    expect(identical(layout.tabs[target.activeTabId]!.session, moved), isTrue);
  });

  test('move leaves the source window when it still has tabs', () {
    final source = layout.addWindow(SshSession());
    final extra = layout.addWindow(SshSession());
    layout.mergeInto(extra.id, source.id);
    final target = layout.addWindow(SshSession());
    final moving = source.tabIds.first;

    final removed = layout.moveTabTo(moving, target.id);

    expect(removed, isNull);
    expect(layout.find(source.id), isNotNull);
    expect(source.tabIds, isNot(contains(moving)));
    expect(target.tabIds, contains(moving));
  });

  test('detach moves one tab into a new window', () {
    final first = layout.addWindow(SshSession());
    final extra = layout.addWindow(SshSession());
    layout.mergeInto(extra.id, first.id);
    final moved = layout.tabs[first.tabIds.last]!.session;

    final created = layout.detachTab(first.id, first.tabIds.last);

    expect(created, isNotNull);
    expect(layout.windows, hasLength(2));
    expect(first.tabIds, hasLength(1));
    expect(created!.tabIds.single, isNot(first.tabIds.single));
    expect(identical(layout.tabs[created.activeTabId]!.session, moved), isTrue);
  });

  test('detach does nothing when the window has a single tab', () {
    final window = layout.addWindow(SshSession());
    expect(layout.detachTab(window.id, window.activeTabId), isNull);
    expect(layout.windows, hasLength(1));
  });

  test('merge keeps the same sessions and drops the source window', () {
    final target = layout.addWindow(SshSession());
    final source = layout.addWindow(SshSession());
    final kept = layout.tabs[source.activeTabId]!.session;

    expect(layout.mergeInto(source.id, target.id), isTrue);

    expect(layout.windows, hasLength(1));
    expect(layout.find(source.id), isNull);
    expect(target.tabIds, hasLength(2));
    expect(
      identical(layout.tabs[target.tabIds.last]!.session, kept),
      isTrue,
    );
  });

  test('merge all windows into one', () {
    final target = layout.addWindow(SshSession());
    layout.addWindow(SshSession());
    layout.addWindow(SshSession());

    final removed = layout.mergeAllInto(target.id);

    expect(removed, hasLength(2));
    expect(layout.windows, hasLength(1));
    expect(target.tabIds, hasLength(3));
  });

  test('closing the last tab removes the window', () {
    final window = layout.addWindow(SshSession());
    final result = layout.closeTab(window.id, window.activeTabId);
    result!.tab.session.dispose();

    expect(result.windowRemoved, isTrue);
    expect(layout.windows, isEmpty);
    expect(layout.tabs, isEmpty);
  });

  test('closing one tab keeps the other active', () {
    final window = layout.addWindow(SshSession());
    final other = layout.addWindow(SshSession());
    layout.mergeInto(other.id, window.id);
    final closing = window.tabIds.first;
    final staying = window.tabIds.last;

    final result = layout.closeTab(window.id, closing);
    result!.tab.session.dispose();

    expect(result.windowRemoved, isFalse);
    expect(window.activeTabId, staying);
    expect(window.tabIds, [staying]);
  });
}
