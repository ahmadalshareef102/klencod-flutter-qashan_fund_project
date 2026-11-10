import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'reports.dart';

const green = Color(0xFF1F4D3A), gold = Color(0xFFC9A227), cream = Color(0xFFF7F5EE), red = Color(0xFFA83C45);
const arMonths = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];

String fmt(num n) => n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
String plain(num n) => n == n.roundToDouble() ? n.round().toString() : n.toString();
String mLabel(String k) { final p = k.split('-'); return '${arMonths[int.parse(p[1]) - 1]} ${p[0]}'; }
String isoToday() => DateTime.now().toIso8601String().substring(0, 10);

/// يقبل الأرقام العربية والفارسية (٣٠٠٠) ويحوّلها لأرقام إنجليزية
String toEn(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = ar.indexOf(ch), j = fa.indexOf(ch);
    if (i >= 0) { b.write(i); }
    else if (j >= 0) { b.write(j); }
    else if (ch == '٫') { b.write('.'); }
    else if (ch == '٬' || ch == '،' || ch == ',' || ch == ' ') { }
    else { b.write(ch); }
  }
  return b.toString();
}
num? parseNum(String s) => num.tryParse(toEn(s));

// ───────────────────────── البيانات ─────────────────────────
class Store extends ChangeNotifier {
  Map<String, dynamic> s = {};
  Directory? dir;
  File? file;
  String saveError = '';
  Future<void> _q = Future.value();

  Future<void> init() async {
    try { dir = await getApplicationDocumentsDirectory(); file = File('${dir!.path}/fund.json'); } catch (_) {}
    Map<String, dynamic>? loaded;
    try { if (file != null && await file!.exists()) loaded = Map<String, dynamic>.from(jsonDecode(await file!.readAsString()) as Map); } catch (_) {}
    if (loaded == null && dir != null) {
      try { final p = File('${dir!.path}/fund_prev.json'); if (await p.exists()) loaded = Map<String, dynamic>.from(jsonDecode(await p.readAsString()) as Map); } catch (_) {}
    }
    loaded ??= Map<String, dynamic>.from(jsonDecode(await rootBundle.loadString('assets/seed.json')) as Map);
    s = normalize(loaded);
    persist();
    await _q;
  }

  /// يحوّل أي نسخة قديمة (تأشيرات سداد) إلى سجل دفعات بالمبالغ
  Map<String, dynamic> normalize(Map<String, dynamic> m) {
    List<Map<String, dynamic>> lst(dynamic x) => [for (final e in (x as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    final members = lst(m['members']);
    final months = [for (final e in (m['months'] as List)) '$e'];
    final payments = <Map<String, dynamic>>[];
    final pay = m['payments'];
    if (pay is List) {
      payments.addAll(lst(pay));
    } else if (pay is Map) {
      final fees = {for (final x in members) x['id']: x['fee']};
      var n = 0;
      pay.forEach((mk, v) {
        (v as Map).forEach((id, ok) {
          if (ok == true && fees.containsKey(id)) {
            payments.add({'id': 'p${n++}', 'mid': id, 'month': '$mk', 'amount': fees[id], 'date': '', 'note': ''});
          }
        });
      });
    }
    var active = '${m['activeMonth'] ?? ''}';
    if (!months.contains(active) && months.isNotEmpty) active = months.last;
    return {'v': 2, 'members': members, 'months': months, 'payments': payments, 'expenses': lst(m['expenses']), 'activeMonth': active};
  }

  void persist() { _q = _q.then((_) => _write()); }

  Future<void> _write() async {
    if (file == null || dir == null) { saveError = 'تعذّر الوصول لمجلد التخزين'; return; }
    try {
      if (await file!.exists()) { try { await file!.copy('${dir!.path}/fund_prev.json'); } catch (_) {} }
      await file!.writeAsString(jsonEncode(s), flush: true);
      if (saveError.isNotEmpty) { saveError = ''; notifyListeners(); }
    } catch (e) {
      saveError = 'تعذّر حفظ البيانات: $e';
      notifyListeners();
    }
  }

  /// يحدّث الشاشة فوراً ثم يحفظ في الملف
  void touch() { notifyListeners(); persist(); }

  List<Map<String, dynamic>> get members => (s['members'] as List).cast<Map<String, dynamic>>();
  List<String> get months => (s['months'] as List).cast<String>();
  List<Map<String, dynamic>> get payments => (s['payments'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get expenses => (s['expenses'] as List).cast<Map<String, dynamic>>();
  String get active => s['activeMonth'] as String;

  String get nowKey { final d = DateTime.now(); return '${d.year}-${d.month.toString().padLeft(2, '0')}'; }
  bool isDue(String mk) => mk.compareTo(nowKey) <= 0;
  num fee(Map m) => (m['fee'] ?? 0) as num;

  num paidAmt(String mk, String id) => payments.where((p) => p['month'] == mk && p['mid'] == id).fold<num>(0, (a, p) => a + (p['amount'] as num));
  bool paid(String mk, String id) { final m = members.where((x) => x['id'] == id); return m.isNotEmpty && paidAmt(mk, id) >= fee(m.first); }
  num monthTotal(String mk) => payments.where((p) => p['month'] == mk).fold<num>(0, (a, p) => a + (p['amount'] as num));
  num get income => payments.fold<num>(0, (a, p) => a + (p['amount'] as num));
  num get spent => expenses.fold<num>(0, (a, e) => a + (e['amount'] as num));
  num get balance => income - spent;
  num expected(String mk) => members.fold<num>(0, (a, m) => a + fee(m));
  num memberPaid(Map m) => payments.where((p) => p['mid'] == m['id']).fold<num>(0, (a, p) => a + (p['amount'] as num));
  List<String> unpaidDue(Map m) => [for (final mk in months) if (isDue(mk) && paidAmt(mk, m['id']) < fee(m)) mk];
  num owed(Map m) => unpaidDue(m).fold<num>(0, (a, mk) => a + (fee(m) - paidAmt(mk, m['id'])));

  void addPayment(String mid, String month, num amount, String date, String note) {
    payments.add({'id': 'p${DateTime.now().microsecondsSinceEpoch}', 'mid': mid, 'month': month, 'amount': amount, 'date': date, 'note': note});
    touch();
  }
  void payFull(String mid, String month) {
    final m = members.firstWhere((x) => x['id'] == mid);
    final rem = fee(m) - paidAmt(month, mid);
    if (rem > 0) addPayment(mid, month, rem, isoToday(), '');
  }
  void delPayment(String id) { payments.removeWhere((p) => p['id'] == id); touch(); }

  void setActive(String mk) { s['activeMonth'] = mk; touch(); }
  void addMonth() {
    final p = months.last.split('-').map(int.parse).toList();
    var y = p[0], m = p[1] + 1;
    if (m > 12) { m = 1; y++; }
    final k = '$y-${m.toString().padLeft(2, '0')}';
    if (!months.contains(k)) months.add(k);
    s['activeMonth'] = k;
    touch();
  }

  void addMember(String name, num fee) { members.add({'id': 'm${DateTime.now().microsecondsSinceEpoch}', 'name': name, 'fee': fee}); touch(); }
  void editMember(String id, String name, num fee) {
    final m = members.firstWhere((x) => x['id'] == id);
    m['name'] = name; m['fee'] = fee;
    touch();
  }
  void delMember(String id) { members.removeWhere((m) => m['id'] == id); payments.removeWhere((p) => p['mid'] == id); touch(); }

  void addExpense(String date, String reason, num amount, String who) {
    expenses.add({'id': 'e${DateTime.now().microsecondsSinceEpoch}', 'date': date, 'reason': reason, 'amount': amount, 'beneficiary': who});
    touch();
  }
  void delExpense(String id) { expenses.removeWhere((e) => e['id'] == id); touch(); }

  void replaceAll(Map<String, dynamic> n) { s = normalize(n); touch(); }
  Future<void> resetSeed() async {
    s = normalize(Map<String, dynamic>.from(jsonDecode(await rootBundle.loadString('assets/seed.json')) as Map));
    touch();
  }
}

final store = Store();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await store.init(); } catch (_) { await store.resetSeed(); }
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'صندوق قعشان',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green, secondary: gold), scaffoldBackgroundColor: cream),
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const Shell(),
      );
}

// ───────────────────────── مساعدات واجهة ─────────────────────────
void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> confirmDo(BuildContext c, String msg, VoidCallback fn) async {
  final ok = await showDialog<bool>(context: c, builder: (ctx) => AlertDialog(
    content: Text(msg),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد'))]));
  if (ok == true) fn();
}

Widget statCard(String t, num v, Color c) => Expanded(
      child: Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
        Text(t, style: const TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('${fmt(v)} ر.ي', style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 14)),
      ]))),
    );

// ───────────────────────── الحوارات ─────────────────────────
Future<void> memberDialog(BuildContext c, {Map<String, dynamic>? m}) async {
  final n = TextEditingController(text: m == null ? '' : '${m['name']}');
  final f = TextEditingController(text: m == null ? '3000' : plain(m['fee'] as num));
  await showDialog(context: c, builder: (ctx) => AlertDialog(
    title: Text(m == null ? 'إضافة عضو' : 'تعديل عضو'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
      TextField(controller: f, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الاشتراك الشهري (ر.ي)')),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
      FilledButton(onPressed: () {
        final name = n.text.trim();
        if (name.isEmpty) return;
        final fee = parseNum(f.text) ?? 0;
        if (m == null) { store.addMember(name, fee); } else { store.editMember(m['id'] as String, name, fee); }
        Navigator.pop(ctx);
      }, child: const Text('حفظ')),
    ]));
}

/// إضافة مبلغ لعضو (أي مبلغ، عن أي شهر)
Future<void> payDialog(BuildContext c, Map<String, dynamic> m, {String? month}) async {
  var mk = month ?? store.active;
  num remOf(String k) { final r = store.fee(m) - store.paidAmt(k, m['id'] as String); return r > 0 ? r : 0; }
  final a = TextEditingController(text: remOf(mk) > 0 ? plain(remOf(mk)) : '');
  final d = TextEditingController(text: isoToday());
  final note = TextEditingController();
  await showDialog(context: c, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
    title: Text('إضافة مبلغ — ${m['name']}'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('عن شهر', style: TextStyle(fontSize: 12, color: Colors.black54)),
      DropdownButton<String>(
        isExpanded: true, value: mk,
        items: [for (final k in store.months) DropdownMenuItem(value: k, child: Text(mLabel(k)))],
        onChanged: (v) { if (v == null) return; setS(() { mk = v; a.text = remOf(v) > 0 ? plain(remOf(v)) : ''; }); }),
      Text('الاشتراك ${fmt(store.fee(m))} — المسدّد ${fmt(store.paidAmt(mk, m['id'] as String))} — المتبقي ${fmt(remOf(mk))} ر.ي', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ (ر.ي)')),
      TextField(controller: d, decoration: const InputDecoration(labelText: 'تاريخ الدفع (yyyy-mm-dd)')),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
      FilledButton(onPressed: () {
        final amt = parseNum(a.text);
        if (amt == null || amt <= 0) { toast(c, 'أدخل مبلغاً صحيحاً'); return; }
        var date = toEn(d.text.trim());
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) date = isoToday();
        store.addPayment(m['id'] as String, mk, amt, date, note.text.trim());
        Navigator.pop(ctx);
        toast(c, 'تمت إضافة ${fmt(amt)} ر.ي لـ ${m['name']}');
      }, child: const Text('حفظ')),
    ])));
}

Future<void> expenseDialog(BuildContext c) async {
  final a = TextEditingController(), r = TextEditingController(), w = TextEditingController(), d = TextEditingController(text: isoToday());
  await showDialog(context: c, builder: (ctx) => AlertDialog(
    title: const Text('تسجيل صرفية'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ (ر.ي)')),
      TextField(controller: r, decoration: const InputDecoration(labelText: 'البيان / سبب الصرف')),
      TextField(controller: w, decoration: const InputDecoration(labelText: 'المستفيد')),
      TextField(controller: d, decoration: const InputDecoration(labelText: 'التاريخ (yyyy-mm-dd)')),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
      FilledButton(onPressed: () {
        final amt = parseNum(a.text);
        if (amt == null || amt <= 0 || r.text.trim().isEmpty) { toast(c, 'أدخل المبلغ والبيان'); return; }
        var date = toEn(d.text.trim());
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) date = isoToday();
        store.addExpense(date, r.text.trim(), amt, w.text.trim());
        Navigator.pop(ctx);
      }, child: const Text('حفظ')),
    ]));
}

// ───────────────────────── الهيكل ─────────────────────────
class Shell extends StatefulWidget { const Shell({super.key}); @override State<Shell> createState() => _ShellState(); }
class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final Widget page = switch (i) { 0 => Home(), 1 => MembersPage(), 2 => ExpensesPage(), 3 => ReportPage(), _ => SettingsPage() };
          return Scaffold(
            appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: const Text('صندوق وتكافل أبناء قعشان', style: TextStyle(fontWeight: FontWeight.bold))),
            body: Column(children: [
              if (store.saveError.isNotEmpty) Container(width: double.infinity, color: red, padding: const EdgeInsets.all(8), child: Text(store.saveError, style: const TextStyle(color: Colors.white, fontSize: 12))),
              Expanded(child: page),
            ]),
            floatingActionButton: i == 1
                ? FloatingActionButton.extended(backgroundColor: green, foregroundColor: Colors.white, onPressed: () => memberDialog(context), icon: const Icon(Icons.person_add), label: const Text('عضو جديد'))
                : i == 2
                    ? FloatingActionButton.extended(backgroundColor: red, foregroundColor: Colors.white, onPressed: () => expenseDialog(context), icon: const Icon(Icons.add), label: const Text('صرفية جديدة'))
                    : null,
            bottomNavigationBar: NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => setState(() => i = v),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'),
                NavigationDestination(icon: Icon(Icons.group_outlined), label: 'الأعضاء'),
                NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'المصروفات'),
                NavigationDestination(icon: Icon(Icons.picture_as_pdf_outlined), label: 'التقارير'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
              ],
            ),
          );
        },
      );
}

// ───────────────────────── الرئيسية ─────────────────────────
void openMember(BuildContext c, String id) => Navigator.push(c, MaterialPageRoute(builder: (_) => MemberPage(id: id)));

class Home extends StatelessWidget {
  const Home({super.key});

  Widget tile(BuildContext c, Map<String, dynamic> m, String mk) {
    final id = m['id'] as String;
    final fee = store.fee(m), p = store.paidAmt(mk, id);
    final full = p >= fee, part = p > 0 && !full;
    final color = full ? green : part ? gold : (store.isDue(mk) ? red : Colors.black38);
    return Card(color: Colors.white, child: ListTile(
      onTap: () => openMember(c, id),
      leading: CircleAvatar(backgroundColor: color.withOpacity(.15), child: Icon(full ? Icons.check : part ? Icons.timelapse : Icons.close, color: color)),
      title: Text('${m['name']}'),
      subtitle: Text(full ? 'مسدّد — ${fmt(p)} ر.ي' : part ? 'مسدّد ${fmt(p)} من ${fmt(fee)} — المتبقي ${fmt(fee - p)}' : 'لم يسدّد — المطلوب ${fmt(fee)} ر.ي'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!full) IconButton(tooltip: 'سداد كامل', icon: const Icon(Icons.done_all, color: green), onPressed: () { store.payFull(id, mk); toast(c, 'تم تسجيل سداد ${m['name']}'); }),
        IconButton(tooltip: 'إضافة مبلغ', icon: const Icon(Icons.add_circle, color: gold, size: 28), onPressed: () => payDialog(c, m, month: mk)),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mk = store.active;
    final mem = store.members;
    final paidCount = mem.where((m) => store.paid(mk, m['id'] as String)).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [statCard('الإيرادات', store.income, green), statCard('المصروفات', store.spent, red), statCard('الرصيد', store.balance, gold)]),
      Card(color: Colors.white, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
        Expanded(child: DropdownButton<String>(
          isExpanded: true, underline: const SizedBox(), value: mk,
          items: [for (final k in store.months.reversed) DropdownMenuItem(value: k, child: Text(mLabel(k)))],
          onChanged: (v) { if (v != null) store.setActive(v); })),
        TextButton.icon(onPressed: store.addMonth, icon: const Icon(Icons.add), label: const Text('شهر جديد')),
      ]))),
      Row(children: [
        Expanded(child: Padding(padding: const EdgeInsets.all(6), child: Text('سدّد كاملاً $paidCount من ${mem.length} — المحصّل ${fmt(store.monthTotal(mk))} من ${fmt(store.expected(mk))} ر.ي', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
        TextButton.icon(onPressed: () => openReport(context, monthlyReport(mk)), icon: const Icon(Icons.picture_as_pdf), label: const Text('تقرير الشهر')),
      ]),
      for (final m in mem) tile(context, m, mk),
      const SizedBox(height: 24),
    ]);
  }
}

// ───────────────────────── صفحة العضو ─────────────────────────
class MemberPage extends StatelessWidget {
  const MemberPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (c, _) {
          final found = store.members.where((x) => x['id'] == id);
          if (found.isEmpty) return Scaffold(appBar: AppBar(), body: const Center(child: Text('العضو غير موجود')));
          final m = found.first;
          final pays = store.payments.where((p) => p['mid'] == id).toList()
            ..sort((a, b) => '${b['date']}${b['id']}'.compareTo('${a['date']}${a['id']}'));
          return Scaffold(
            appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: Text('${m['name']}'), actions: [
              IconButton(tooltip: 'كشف حساب PDF', icon: const Icon(Icons.picture_as_pdf), onPressed: () => openReport(c, memberReport(m))),
              IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit), onPressed: () => memberDialog(c, m: m)),
            ]),
            floatingActionButton: FloatingActionButton.extended(backgroundColor: gold, foregroundColor: Colors.white, onPressed: () => payDialog(c, m), icon: const Icon(Icons.add), label: const Text('إضافة مبلغ')),
            body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
              Row(children: [statCard('الاشتراك الشهري', store.fee(m), gold), statCard('إجمالي المسدّد', store.memberPaid(m), green), statCard('المتأخرات', store.owed(m), store.owed(m) > 0 ? red : green)]),
              const Padding(padding: EdgeInsets.fromLTRB(6, 8, 6, 4), child: Text('الأشهر', style: TextStyle(fontWeight: FontWeight.bold))),
              for (final k in store.months.reversed)
                (() {
                  final p = store.paidAmt(k, id), f = store.fee(m);
                  final full = p >= f, part = p > 0 && !full, due = store.isDue(k);
                  final col = full ? green : part ? gold : (due ? red : Colors.black38);
                  return Card(color: Colors.white, child: ListTile(
                    dense: true,
                    leading: Icon(full ? Icons.check_circle : part ? Icons.timelapse : (due ? Icons.cancel : Icons.remove_circle_outline), color: col),
                    title: Text(mLabel(k)),
                    subtitle: Text(full ? 'مسدّد ${fmt(p)}' : part ? 'مسدّد ${fmt(p)} — المتبقي ${fmt(f - p)}' : (due ? 'غير مسدّد' : 'غير مستحق بعد')),
                    trailing: IconButton(icon: const Icon(Icons.add_circle_outline, color: gold), onPressed: () => payDialog(c, m, month: k)),
                  ));
                })(),
              const Padding(padding: EdgeInsets.fromLTRB(6, 12, 6, 4), child: Text('سجل الدفعات', style: TextStyle(fontWeight: FontWeight.bold))),
              if (pays.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('لا توجد دفعات'))),
              for (final p in pays)
                Card(color: Colors.white, child: ListTile(
                  dense: true,
                  title: Text('${fmt(p['amount'] as num)} ر.ي — ${mLabel(p['month'] as String)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${(p['date'] ?? '').toString().isEmpty ? 'بدون تاريخ' : p['date']}${(p['note'] ?? '').toString().isEmpty ? '' : '  •  ${p['note']}'}'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: red), onPressed: () => confirmDo(c, 'حذف هذه الدفعة؟', () => store.delPayment(p['id'] as String))),
                )),
            ]),
          );
        },
      );
}

// ───────────────────────── الأعضاء ─────────────────────────
class MembersPage extends StatelessWidget {
  const MembersPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        for (final (i, m) in store.members.indexed)
          Card(color: Colors.white, child: ListTile(
            onTap: () => openMember(context, m['id'] as String),
            leading: CircleAvatar(backgroundColor: green, foregroundColor: Colors.white, child: Text('${i + 1}')),
            title: Text('${m['name']}'),
            subtitle: Text('الاشتراك ${fmt(store.fee(m))} • المسدّد ${fmt(store.memberPaid(m))}${store.owed(m) > 0 ? ' • متأخر ${fmt(store.owed(m))}' : ''}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => memberDialog(context, m: m)),
              IconButton(icon: const Icon(Icons.delete_outline, color: red), onPressed: () => confirmDo(context, 'حذف العضو "${m['name']}" وكل دفعاته؟', () => store.delMember(m['id'] as String))),
            ]))),
      ]);
}

// ───────────────────────── المصروفات ─────────────────────────
class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final list = store.expenses.toList()..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
      Row(children: [statCard('إجمالي المصروفات', store.spent, red), statCard('الرصيد المتوفر', store.balance, green)]),
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد مصروفات مسجّلة'))),
      for (final e in list)
        Card(color: Colors.white, child: ListTile(
          title: Text('${e['reason']}'),
          subtitle: Text('${e['date']}${'${e['beneficiary'] ?? ''}'.isEmpty ? '' : '  •  ${e['beneficiary']}'}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(fmt(e['amount'] as num), style: const TextStyle(color: red, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => confirmDo(context, 'حذف هذه الصرفية؟', () => store.delExpense(e['id'] as String))),
          ]))),
    ]);
  }
}

// ───────────────────────── الإعدادات ─────────────────────────
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        Card(color: Colors.white, child: ListTile(
          leading: const Icon(Icons.upload_file, color: green), title: const Text('تصدير نسخة احتياطية'),
          subtitle: const Text('احفظ الملف في واتساب أو Drive أو أي مكان آمن'),
          onTap: () async {
            try {
              final f = File('${(await getTemporaryDirectory()).path}/qashan_fund_backup_${isoToday()}.json');
              await f.writeAsString(const JsonEncoder.withIndent('  ').convert(store.s));
              await Share.shareXFiles([XFile(f.path)]);
            } catch (e) { if (context.mounted) toast(context, 'تعذّر التصدير: $e'); }
          })),
        Card(color: Colors.white, child: ListTile(
          leading: const Icon(Icons.download, color: green), title: const Text('استيراد نسخة احتياطية'),
          subtitle: const Text('يقبل النسخ القديمة والجديدة'),
          onTap: () async {
            final r = await FilePicker.platform.pickFiles();
            if (r == null || r.files.single.path == null) return;
            try {
              final m = Map<String, dynamic>.from(jsonDecode(await File(r.files.single.path!).readAsString()) as Map);
              if (m['members'] == null || m['months'] == null) throw 'x';
              store.normalize(m);
              if (!context.mounted) return;
              confirmDo(context, 'سيتم استبدال البيانات الحالية. متابعة؟', () { store.replaceAll(m); toast(context, 'تم الاستيراد'); });
            } catch (_) { if (context.mounted) toast(context, 'ملف غير صالح'); }
          })),
        Card(color: Colors.white, child: ListTile(
          leading: const Icon(Icons.restore, color: red), title: const Text('إعادة البيانات المستعادة الأصلية'),
          onTap: () => confirmDo(context, 'استبدال كل البيانات بالنسخة المستعادة من تقرير سبتمبر؟', () => store.resetSeed()))),
        const Padding(padding: EdgeInsets.all(16), child: Text('تُحفظ البيانات داخل التطبيق مع نسخة سابقة تلقائية. صدّر نسخة احتياطية بعد كل تحديث. لو ظهر شريط أحمر بأعلى الشاشة فالحفظ فشل.', style: TextStyle(color: Colors.black54))),
      ]);
}