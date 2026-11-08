import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

const green = Color(0xFF1F4D3A), gold = Color(0xFFC9A227), cream = Color(0xFFF7F5EE), red = Color(0xFFA83C45);
const arMonths = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];

String fmt(num n) => n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
String mLabel(String k) { final p = k.split('-'); return '${arMonths[int.parse(p[1]) - 1]} ${p[0]}'; }

class Store extends ChangeNotifier {
  Map<String, dynamic> s = {};
  late Directory dir;
  late File file;

  Future<void> init() async {
    dir = await getApplicationDocumentsDirectory();
    file = File('${dir.path}/fund.json');
    try {
      if (await file.exists()) { s = jsonDecode(await file.readAsString()); }
      else { await seed(); }
    } catch (_) {
      final prev = File('${dir.path}/fund_prev.json');
      if (await prev.exists()) { s = jsonDecode(await prev.readAsString()); } else { await seed(); }
    }
    s['expenses'] ??= [];
  }

  Future<void> seed() async { s = jsonDecode(await rootBundle.loadString('assets/seed.json')); await save(); }

  Future<void> save() async {
    if (await file.exists()) { await file.copy('${dir.path}/fund_prev.json'); }
    final tmp = File('${dir.path}/fund.tmp');
    await tmp.writeAsString(jsonEncode(s));
    await tmp.rename(file.path);
    notifyListeners();
  }

  List get members => s['members'];
  List get months => s['months'];
  List get expenses => s['expenses'];
  String get active => s['activeMonth'];

  bool paid(String mk, String id) => ((s['payments'][mk] ?? {}) as Map)[id] == true;
  num fee(Map m) => (m['fee'] ?? 0) as num;
  num monthTotal(String mk) => members.fold<num>(0, (a, m) => a + (paid(mk, m['id']) ? fee(m) : 0));
  num get income => months.fold<num>(0, (a, mk) => a + monthTotal(mk));
  num get spent => expenses.fold<num>(0, (a, e) => a + (e['amount'] as num));
  num get balance => income - spent;

  Future<void> toggle(String mk, String id) async {
    (s['payments'] as Map).putIfAbsent(mk, () => <String, dynamic>{});
    s['payments'][mk][id] = !paid(mk, id);
    await save();
  }
  Future<void> setActive(String mk) async { s['activeMonth'] = mk; await save(); }
  Future<void> addMonth() async {
    final p = (months.last as String).split('-').map(int.parse).toList();
    var y = p[0], m = p[1] + 1;
    if (m > 12) { m = 1; y++; }
    final k = '$y-${m.toString().padLeft(2, '0')}';
    if (!months.contains(k)) { months.add(k); (s['payments'] as Map)[k] = <String, dynamic>{}; }
    s['activeMonth'] = k;
    await save();
  }
  Future<void> addMember(String name, num fee) async {
    members.add({'id': 'm${DateTime.now().millisecondsSinceEpoch}', 'name': name, 'fee': fee});
    await save();
  }
  Future<void> delMember(String id) async {
    members.removeWhere((m) => m['id'] == id);
    for (final p in (s['payments'] as Map).values) { (p as Map).remove(id); }
    await save();
  }
  Future<void> addExpense(String date, String reason, num amount, String who) async {
    expenses.add({'id': 'e${DateTime.now().millisecondsSinceEpoch}', 'date': date, 'reason': reason, 'amount': amount, 'beneficiary': who});
    await save();
  }
  Future<void> delExpense(String id) async { expenses.removeWhere((e) => e['id'] == id); await save(); }
  Future<void> replaceAll(Map<String, dynamic> n) async { s = n; s['expenses'] ??= []; await save(); }
}

final store = Store();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
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

class Shell extends StatefulWidget { const Shell({super.key}); @override State<Shell> createState() => _ShellState(); }
class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const Home(), const MembersPage(), const ExpensesPage(), const ReportPage(), const SettingsPage()];
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) => Scaffold(
        appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: const Text('صندوق وتكافل أبناء قعشان', style: TextStyle(fontWeight: FontWeight.bold))),
        body: pages[i],
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.group_outlined), label: 'الأعضاء'),
            NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'المصروفات'),
            NavigationDestination(icon: Icon(Icons.table_chart_outlined), label: 'التقرير'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }
}

Widget statCard(String t, num v, Color c) => Expanded(
      child: Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
        Text(t, style: const TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('${fmt(v)} ر.ي', style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 14)),
      ]))),
    );

Future<void> confirmDo(BuildContext c, String msg, Future<void> Function() fn) async {
  final ok = await showDialog<bool>(context: c, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
    content: Text(msg),
    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد'))])));
  if (ok == true) await fn();
}

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext context) {
    final mk = store.active;
    final paidCount = store.members.where((m) => store.paid(mk, m['id'])).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [statCard('الإيرادات', store.income, green), statCard('المصروفات', store.spent, red), statCard('الرصيد', store.balance, gold)]),
      Card(color: Colors.white, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
        Expanded(child: DropdownButton<String>(
          isExpanded: true, underline: const SizedBox(), value: mk,
          items: [for (final k in store.months.reversed) DropdownMenuItem(value: k as String, child: Text(mLabel(k)))],
          onChanged: (v) => store.setActive(v!))),
        TextButton.icon(onPressed: store.addMonth, icon: const Icon(Icons.add), label: const Text('شهر جديد')),
      ]))),
      Padding(padding: const EdgeInsets.all(6), child: Text('سدّد $paidCount من ${store.members.length} — المحصّل ${fmt(store.monthTotal(mk))} ر.ي', style: const TextStyle(fontWeight: FontWeight.bold))),
      for (final m in store.members)
        Card(color: Colors.white, child: CheckboxListTile(
          activeColor: green,
          value: store.paid(mk, m['id']),
          onChanged: (_) => store.toggle(mk, m['id']),
          title: Text(m['name']),
          subtitle: Text('${fmt(store.fee(m))} ر.ي'),
        )),
    ]);
  }
}

class MembersPage extends StatelessWidget {
  const MembersPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: green, foregroundColor: Colors.white,
          onPressed: () => _add(context), icon: const Icon(Icons.person_add), label: const Text('عضو جديد')),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
          for (final (i, m) in store.members.indexed)
            Card(color: Colors.white, child: ListTile(
              leading: CircleAvatar(backgroundColor: green, foregroundColor: Colors.white, child: Text('${i + 1}')),
              title: Text(m['name']), subtitle: Text('الاشتراك: ${fmt(store.fee(m))} ر.ي'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: red),
                onPressed: () => confirmDo(context, 'حذف العضو "${m['name']}" وكل سجل سداده؟', () => store.delMember(m['id']))))),
        ]),
      );

  void _add(BuildContext c) {
    final n = TextEditingController(), f = TextEditingController(text: '3000');
    showDialog(context: c, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: const Text('إضافة عضو'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
        TextField(controller: f, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الاشتراك الشهري (ر.ي)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () { if (n.text.trim().isEmpty) return; store.addMember(n.text.trim(), num.tryParse(f.text) ?? 0); Navigator.pop(c); }, child: const Text('حفظ'))])));
  }
}

class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final list = store.expenses.toList()..sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: red, foregroundColor: Colors.white,
        onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('صرفية جديدة')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        Row(children: [statCard('إجمالي المصروفات', store.spent, red), statCard('الرصيد المتوفر', store.balance, green)]),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد مصروفات مسجّلة'))),
        for (final e in list)
          Card(color: Colors.white, child: ListTile(
            title: Text(e['reason']),
            subtitle: Text('${e['date']}${(e['beneficiary'] ?? '').toString().isEmpty ? '' : '  •  ${e['beneficiary']}'}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fmt(e['amount']), style: const TextStyle(color: red, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => confirmDo(context, 'حذف هذه الصرفية؟', () => store.delExpense(e['id']))),
            ]))),
      ]),
    );
  }

  void _add(BuildContext c) {
    final a = TextEditingController(), r = TextEditingController(), w = TextEditingController();
    final d = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    showDialog(context: c, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: const Text('تسجيل صرفية'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ (ر.ي)')),
        TextField(controller: r, decoration: const InputDecoration(labelText: 'البيان / سبب الصرف')),
        TextField(controller: w, decoration: const InputDecoration(labelText: 'المستفيد')),
        TextField(controller: d, decoration: const InputDecoration(labelText: 'التاريخ (yyyy-mm-dd)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () {
          final amt = num.tryParse(a.text) ?? 0;
          if (amt <= 0 || r.text.trim().isEmpty) { toast(c, 'أدخل المبلغ والبيان'); return; }
          store.addExpense(d.text.trim(), r.text.trim(), amt, w.text.trim());
          Navigator.pop(c);
        }, child: const Text('حفظ'))])));
  }
}

class ReportPage extends StatelessWidget {
  const ReportPage({super.key});
  @override
  Widget build(BuildContext context) {
    final ms = store.months.cast<String>();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [statCard('إجمالي الإيرادات', store.income, green), statCard('المصروفات', store.spent, red), statCard('الرصيد', store.balance, gold)]),
      const SizedBox(height: 8),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Card(color: Colors.white, child: DataTable(
        columnSpacing: 18, headingRowHeight: 44, dataRowMinHeight: 38, dataRowMaxHeight: 38,
        columns: [const DataColumn(label: Text('العضو')), for (final k in ms) DataColumn(label: Text(mLabel(k), style: const TextStyle(fontSize: 11)))],
        rows: [
          for (final m in store.members)
            DataRow(cells: [DataCell(Text(m['name'])), for (final k in ms) DataCell(Text(store.paid(k, m['id']) ? '✅' : '❌'))]),
          DataRow(color: WidgetStatePropertyAll(green.withOpacity(.08)), cells: [
            const DataCell(Text('المحصّل', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final k in ms) DataCell(Text(fmt(store.monthTotal(k)), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
        ],
      ))),
    ]);
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        Card(color: Colors.white, child: ListTile(
          leading: const Icon(Icons.upload_file, color: green), title: const Text('تصدير نسخة احتياطية'),
          subtitle: const Text('احفظ الملف في واتساب أو Drive أو أي مكان آمن'),
          onTap: () async {
            final f = File('${(await getTemporaryDirectory()).path}/qashan_fund_backup_${DateTime.now().toIso8601String().substring(0, 10)}.json');
            await f.writeAsString(const JsonEncoder.withIndent('  ').convert(store.s));
            await Share.shareXFiles([XFile(f.path)]);
          })),
        Card(color: Colors.white, child: ListTile(
          leading: const Icon(Icons.download, color: green), title: const Text('استيراد نسخة احتياطية'),
          onTap: () async {
            final r = await FilePicker.platform.pickFiles();
            if (r == null || r.files.single.path == null) return;
            try {
              final m = jsonDecode(await File(r.files.single.path!).readAsString()) as Map<String, dynamic>;
              if (m['members'] == null || m['months'] == null || m['payments'] == null) throw 'x';
              if (!context.mounted) return;
              confirmDo(context, 'سيتم استبدال البيانات الحالية. متابعة؟', () async { await store.replaceAll(m); if (context.mounted) toast(context, 'تم الاستيراد'); });
            } catch (_) { if (context.mounted) toast(context, 'ملف غير صالح'); }
          })),
        Card(color: Colors.white, child: ListTile(
          leading: const Icon(Icons.restore, color: red), title: const Text('إعادة البيانات المستعادة الأصلية'),
          onTap: () => confirmDo(context, 'استبدال كل البيانات بالنسخة المستعادة من تقرير سبتمبر؟', store.seed))),
        const Padding(padding: EdgeInsets.all(16), child: Text('تُحفظ البيانات داخل التطبيق مع نسخة سابقة تلقائية، ولا تُمسح بمسح بيانات المتصفح. صدّر نسخة احتياطية بعد كل تحديث.', style: TextStyle(color: Colors.black54))),
      ]);
}