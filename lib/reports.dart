import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'main.dart';

const pageW = 1123.0, pageH = 794.0; // A4 landscape
const lineC = Color(0xFFE5E1D3), headBg = Color(0xFFEFEBDC), zebra = Color(0xFFFBFAF5), totBg = Color(0xFFE3EDE6);

String today() { final d = DateTime.now(); return '${d.year}/${d.month}/${d.day}'; }
String mShort(String k) => arMonths[int.parse(k.split('-')[1]) - 1];

class Spec {
  Spec(this.title, this.subtitle, this.file, this.bodies);
  final String title, subtitle, file;
  final List<Widget> bodies;
}

class Stat { Stat(this.label, this.value, this.color); final String label, value; final Color color; }

class Col {
  Col(this.head, {this.w, this.flex = 1, this.al = Alignment.center});
  final Widget head; final double? w; final int flex; final AlignmentGeometry al;
}

List<List<T>> paged<T>(List<T> items, int firstCap, int cap) {
  if (items.isEmpty) return [<T>[]];
  final out = <List<T>>[];
  var i = 0, c = firstCap;
  while (i < items.length) {
    final e = i + c > items.length ? items.length : i + c;
    out.add(items.sublist(i, e));
    i = e; c = cap;
  }
  return out;
}

Widget txt(String s, {double size = 12, Color? color, bool bold = false, TextAlign align = TextAlign.center}) => Text(s,
    style: TextStyle(fontSize: size, color: color ?? Colors.black87, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, height: 1.2),
    textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis);

Widget ht(String s) => txt(s, size: 12, bold: true, color: green);

Widget cell(Widget child, {double? w, int flex = 1, double h = 24, Color? bg, AlignmentGeometry al = Alignment.center}) {
  final c = Container(
    height: h, alignment: al, padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(color: bg, border: const Border(bottom: BorderSide(color: lineC))), child: child);
  return w != null ? SizedBox(width: w, child: c) : Expanded(flex: flex, child: c);
}

Widget table(List<Col> cols, List<List<Widget>> rows, {List<Widget>? total}) {
  Widget line(List<Widget> ch, {Color? bg, double h = 24}) => Row(children: [
        for (var i = 0; i < cols.length; i++) cell(ch[i], w: cols[i].w, flex: cols[i].flex, al: cols[i].al, bg: bg, h: h)
      ]);
  return Column(children: [
    line([for (final c in cols) c.head], bg: headBg, h: 38),
    for (var r = 0; r < rows.length; r++) line(rows[r], bg: r.isEven ? Colors.white : zebra),
    if (total != null) line(total, bg: totBg, h: 28),
  ]);
}

Widget summaryRow(List<Stat> items) => Row(children: [
      for (final it in items)
        Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(color: cream, border: Border.all(color: lineC), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            txt(it.label, size: 11, color: Colors.black54),
            const SizedBox(height: 4),
            txt(it.value, size: 18, bold: true, color: it.color),
          ]))),
    ]);

Widget emptyNote(String s) => Padding(padding: const EdgeInsets.all(40), child: Center(child: txt(s, size: 16, color: Colors.black45)));

Widget statusMark(bool paid, bool due) {
  if (paid) return const Icon(Icons.check_circle, color: green, size: 16);
  if (due) return const Icon(Icons.cancel, color: red, size: 16);
  return txt('–', color: Colors.black26);
}

Widget payCell(String mk, Map m) {
  final p = store.paidAmt(mk, m['id']), f = store.fee(m);
  if (p >= f) return const Icon(Icons.check_circle, color: green, size: 16);
  if (p > 0) return txt(fmt(p), size: 10, bold: true, color: gold);
  return store.isDue(mk) ? const Icon(Icons.cancel, color: red, size: 16) : txt('–', color: Colors.black26);
}

Widget statusRow(String mk, Map m) {
  final p = store.paidAmt(mk, m['id']), f = store.fee(m), due = store.isDue(mk);
  final full = p >= f, part = p > 0 && !full;
  final label = full ? 'مسدّد' : part ? 'مسدّد جزئياً' : (due ? 'غير مسدّد' : 'غير مستحق');
  final color = full ? green : part ? gold : (due ? red : Colors.black45);
  final icon = full ? Icons.check_circle : part ? Icons.timelapse : (due ? Icons.cancel : Icons.remove_circle_outline);
  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color, size: 16), const SizedBox(width: 6), txt(label, color: color, bold: true)]);
}

Widget pageBody(List<Widget> kids) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids);

// ───────────── التقارير ─────────────

Spec comprehensiveReport() {
  final ms = store.months.cast<String>();
  final mem = store.members.cast<Map>();
  final groups = <List<String>>[];
  for (var i = 0; i < ms.length; i += 12) { groups.add(ms.sublist(i, i + 12 > ms.length ? ms.length : i + 12)); }
  final bodies = <Widget>[];
  for (var g = 0; g < groups.length; g++) {
    final gm = groups[g];
    final chunks = paged<Map>(mem, g == 0 ? 18 : 22, 22);
    var off = 0;
    for (var c = 0; c < chunks.length; c++) {
      final ch = chunks[c];
      final last = c == chunks.length - 1;
      final cols = [
        Col(ht('#'), w: 36),
        Col(ht('اسم العضو'), w: 210, al: AlignmentDirectional.centerStart),
        for (final k in gm) Col(Column(mainAxisAlignment: MainAxisAlignment.center, children: [txt(mShort(k), size: 10.5, bold: true, color: green), txt(k.split('-')[0], size: 9, color: Colors.black45)])),
        Col(ht('إجمالي العضو'), w: 100),
      ];
      final rows = [
        for (var i = 0; i < ch.length; i++)
          [
            txt('${off + i + 1}', color: Colors.black54),
            txt(ch[i]['name'], align: TextAlign.start),
            for (final k in gm) payCell(k, ch[i]),
            txt(fmt(store.memberPaid(ch[i])), bold: true),
          ]
      ];
      final total = last
          ? [
              txt(''),
              txt('المحصّل الشهري', bold: true, color: green, align: TextAlign.start),
              for (final k in gm) txt(fmt(store.monthTotal(k)), size: 10.5, bold: true),
              txt(fmt(store.income), bold: true, color: green),
            ]
          : null;
      bodies.add(pageBody([
        if (g == 0 && c == 0) ...[
          summaryRow([Stat('إجمالي إيرادات الصندوق (الاشتراكات المسدّدة)', '${fmt(store.income)} ر.ي', green), Stat('إجمالي المصروفات والسحبيات', '${fmt(store.spent)} ر.ي', red), Stat('الرصيد المتوفر حاليًا في الصندوق', '${fmt(store.balance)} ر.ي', gold)]),
          const SizedBox(height: 10),
        ],
        table(cols, rows, total: total),
      ]));
      off += ch.length;
    }
  }
  return Spec('التقرير الشامل لجميع الأشهر', 'عدد الأشهر المدرجة: ${ms.length}  •  عدد الأعضاء: ${mem.length}', 'comprehensive', bodies);
}

Spec monthlyReport(String mk) {
  final mem = store.members.cast<Map>();
  final paidN = mem.where((m) => store.paid(mk, m['id'])).length;
  final got = store.monthTotal(mk), exp = store.expected(mk), due = store.isDue(mk);
  final chunks = paged<Map>(mem, 18, 22);
  final cols = [Col(ht('#'), w: 36), Col(ht('اسم العضو'), flex: 3, al: AlignmentDirectional.centerStart), Col(ht('الاشتراك'), w: 120), Col(ht('الحالة'), w: 150), Col(ht('المبلغ المسدّد'), w: 130)];
  final bodies = <Widget>[];
  var off = 0;
  for (var c = 0; c < chunks.length; c++) {
    final ch = chunks[c];
    final rows = [
      for (var i = 0; i < ch.length; i++)
        (() {
          return <Widget>[
            txt('${off + i + 1}', color: Colors.black54),
            txt(ch[i]['name'], align: TextAlign.start),
            txt(fmt(store.fee(ch[i]))),
            statusRow(mk, ch[i]),
            txt(fmt(store.paidAmt(mk, ch[i]['id']))),
          ];
        })()
    ];
    final last = c == chunks.length - 1;
    bodies.add(pageBody([
      if (c == 0) ...[
        summaryRow([Stat('المحصّل هذا الشهر', '${fmt(got)} ر.ي', green), Stat('المتوقع تحصيله', '${fmt(exp)} ر.ي', gold), Stat('المتبقي', '${fmt(exp - got)} ر.ي', red), Stat('سدّد', '$paidN من ${mem.length}', Colors.black87)]),
        const SizedBox(height: 10),
      ],
      table(cols, rows, total: last ? [txt(''), txt('الإجمالي', bold: true, color: green, align: TextAlign.start), txt(fmt(exp), bold: true), txt('$paidN / ${mem.length}', bold: true), txt(fmt(got), bold: true, color: green)] : null),
    ]));
    off += ch.length;
  }
  return Spec('التقرير الشهري', mLabel(mk), 'month_$mk', bodies);
}

Spec memberReport(Map m) {
  final ms = store.months.cast<String>();
  final fee = store.fee(m);
  final paidN = ms.where((k) => store.paid(k, m['id'])).length;
  final owedN = store.unpaidDue(m).length;
  final chunks = paged<String>(ms, 18, 22);
  final cols = [Col(ht('#'), w: 36), Col(ht('الشهر'), flex: 2, al: AlignmentDirectional.centerStart), Col(ht('الحالة'), w: 170), Col(ht('المبلغ'), w: 140)];
  final bodies = <Widget>[];
  var off = 0;
  for (var c = 0; c < chunks.length; c++) {
    final ch = chunks[c];
    final rows = [
      for (var i = 0; i < ch.length; i++)
        (() {
          return <Widget>[
            txt('${off + i + 1}', color: Colors.black54),
            txt(mLabel(ch[i]), align: TextAlign.start),
            statusRow(ch[i], m),
            txt(fmt(store.paidAmt(ch[i], m['id']))),
          ];
        })()
    ];
    final last = c == chunks.length - 1;
    bodies.add(pageBody([
      if (c == 0) ...[
        summaryRow([Stat('الاشتراك الشهري', '${fmt(fee)} ر.ي', gold), Stat('إجمالي ما سدّده', '${fmt(store.memberPaid(m))} ر.ي', green), Stat('الأشهر المسدّدة', '$paidN من ${ms.length}', Colors.black87), Stat('المتأخرات المستحقة', '${fmt(store.owed(m))} ر.ي', owedN == 0 ? green : red)]),
        const SizedBox(height: 10),
      ],
      table(cols, rows, total: last ? [txt(''), txt('الإجمالي المسدّد', bold: true, color: green, align: TextAlign.start), txt('$paidN شهر', bold: true), txt(fmt(store.memberPaid(m)), bold: true, color: green)] : null),
    ]));
    off += ch.length;
  }
  return Spec('كشف حساب عضو', '${m['name']}', 'member', bodies);
}

Spec expensesReport() {
  final list = store.expenses.cast<Map>().toList()..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
  final cols = [Col(ht('#'), w: 36), Col(ht('التاريخ'), w: 120), Col(ht('البيان'), flex: 3, al: AlignmentDirectional.centerStart), Col(ht('المستفيد'), flex: 2, al: AlignmentDirectional.centerStart), Col(ht('المبلغ (ر.ي)'), w: 130)];
  final chunks = paged<Map>(list, 18, 22);
  final bodies = <Widget>[];
  var off = 0;
  for (var c = 0; c < chunks.length; c++) {
    final ch = chunks[c];
    final rows = [
      for (var i = 0; i < ch.length; i++)
        <Widget>[txt('${off + i + 1}', color: Colors.black54), txt('${ch[i]['date']}'), txt('${ch[i]['reason']}', align: TextAlign.start), txt('${ch[i]['beneficiary'] ?? ''}', align: TextAlign.start), txt(fmt(ch[i]['amount']), bold: true, color: red)]
    ];
    final last = c == chunks.length - 1;
    bodies.add(pageBody([
      if (c == 0) ...[
        summaryRow([Stat('إجمالي المصروفات والسحبيات', '${fmt(store.spent)} ر.ي', red), Stat('عدد العمليات', '${list.length}', Colors.black87), Stat('الرصيد المتوفر حاليًا', '${fmt(store.balance)} ر.ي', green)]),
        const SizedBox(height: 10),
      ],
      table(cols, rows, total: last && list.isNotEmpty ? [txt(''), txt(''), txt('الإجمالي', bold: true, color: green, align: TextAlign.start), txt(''), txt(fmt(store.spent), bold: true, color: red)] : null),
      if (list.isEmpty) emptyNote('لا توجد مصروفات أو سحبيات مسجّلة'),
    ]));
    off += ch.length;
  }
  return Spec('تفاصيل المصروفات والسحبيات', 'إجمالي ${list.length} عملية', 'expenses', bodies);
}

Spec arrearsReport() {
  final mem = store.members.cast<Map>();
  num owedOf(Map m) => store.owed(m);
  final rowsM = mem.where((m) => store.unpaidDue(m).isNotEmpty).toList()..sort((a, b) => owedOf(b).compareTo(owedOf(a)));
  final totalOwed = rowsM.fold<num>(0, (a, m) => a + owedOf(m));
  final dueN = store.months.cast<String>().where(store.isDue).length;
  final cols = [Col(ht('#'), w: 36), Col(ht('اسم العضو'), flex: 2, al: AlignmentDirectional.centerStart), Col(ht('عدد الأشهر'), w: 100), Col(ht('الأشهر غير المسدّدة'), flex: 4, al: AlignmentDirectional.centerStart), Col(ht('المبلغ المتأخر'), w: 130)];
  final chunks = paged<Map>(rowsM, 18, 22);
  final bodies = <Widget>[];
  var off = 0;
  for (var c = 0; c < chunks.length; c++) {
    final ch = chunks[c];
    final rows = [
      for (var i = 0; i < ch.length; i++)
        <Widget>[txt('${off + i + 1}', color: Colors.black54), txt(ch[i]['name'], align: TextAlign.start), txt('${store.unpaidDue(ch[i]).length}'), txt(store.unpaidDue(ch[i]).map(mShort).join('، '), size: 11, align: TextAlign.start), txt(fmt(owedOf(ch[i])), bold: true, color: red)]
    ];
    final last = c == chunks.length - 1;
    bodies.add(pageBody([
      if (c == 0) ...[
        summaryRow([Stat('إجمالي المتأخرات', '${fmt(totalOwed)} ر.ي', red), Stat('عدد المتأخرين', '${rowsM.length} من ${mem.length}', Colors.black87), Stat('الأشهر المستحقة حتى الآن', '$dueN', gold)]),
        const SizedBox(height: 10),
      ],
      table(cols, rows, total: last && rowsM.isNotEmpty ? [txt(''), txt('الإجمالي', bold: true, color: green, align: TextAlign.start), txt(''), txt(''), txt(fmt(totalOwed), bold: true, color: red)] : null),
      if (rowsM.isEmpty) emptyNote('لا توجد متأخرات — جميع الأعضاء مسدّدون'),
    ]));
    off += ch.length;
  }
  return Spec('تقرير المتأخرات', 'حتى ${mLabel(store.nowKey)}', 'arrears', bodies);
}

// ───────────── الصفحة (A4 أفقي) ─────────────

class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.spec, required this.no, required this.count});
  final Spec spec; final int no, count;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: pageW, height: pageH,
        child: Material(color: Colors.white, child: Directionality(textDirection: TextDirection.rtl, child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Container(
              height: 64, padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('صندوق وتكافل أبناء قعشان', style: const TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(spec.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                ]),
                const Spacer(),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(spec.subtitle, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(today(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            Expanded(child: spec.bodies[no - 1]),
            SizedBox(height: 24, child: Row(children: [
              Expanded(child: txt('صندوق وتكافل أبناء قعشان — من أبناء قعشان .. إلى أبناء قعشان  ·  تم إنشاء التقرير بتاريخ ${today()}', size: 10, color: Colors.black54, align: TextAlign.start)),
              txt('صفحة $no من $count', size: 10, color: Colors.black54),
            ])),
          ]),
        ))),
      );
}

// ───────────── المعاينة والتصدير ─────────────

void openReport(BuildContext c, Spec s) => Navigator.push(c, MaterialPageRoute(builder: (_) => Preview(spec: s)));

class Preview extends StatefulWidget {
  const Preview({super.key, required this.spec});
  final Spec spec;
  @override
  State<Preview> createState() => _PreviewState();
}

class _PreviewState extends State<Preview> {
  late final List<GlobalKey> keys = List<GlobalKey>.generate(widget.spec.bodies.length, (_) => GlobalKey());
  bool busy = false;

  String get stamp => DateTime.now().toIso8601String().substring(0, 10);

  Future<List<Uint8List>> capture() async {
    await WidgetsBinding.instance.endOfFrame;
    final out = <Uint8List>[];
    for (final k in keys) {
      final ro = k.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await ro.toImage(pixelRatio: 2.2);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      out.add(bd!.buffer.asUint8List());
    }
    return out;
  }

  Future<void> run(Future<void> Function() job) async {
    setState(() => busy = true);
    try { await job(); } catch (e) { if (mounted) toast(context, 'تعذّر إنشاء التقرير: $e'); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> sharePdf() => run(() async {
        final shots = await capture();
        final pf = PdfPageFormat.a4.landscape;
        final doc = pw.Document();
        for (final b in shots) {
          final img = pw.MemoryImage(b);
          doc.addPage(pw.Page(pageFormat: pf, margin: pw.EdgeInsets.zero, build: (_) => pw.Image(img, width: pf.width, height: pf.height, fit: pw.BoxFit.fill)));
        }
        final f = File('${(await getTemporaryDirectory()).path}/qashan_${widget.spec.file}_$stamp.pdf');
        await f.writeAsBytes(await doc.save());
        await Share.shareXFiles([XFile(f.path)], subject: widget.spec.title);
      });

  Future<void> shareImages() => run(() async {
        final shots = await capture();
        final dir = (await getTemporaryDirectory()).path;
        final files = <XFile>[];
        for (var i = 0; i < shots.length; i++) {
          final f = File('$dir/qashan_${widget.spec.file}_${stamp}_${i + 1}.png');
          await f.writeAsBytes(shots[i]);
          files.add(XFile(f.path));
        }
        await Share.shareXFiles(files, subject: widget.spec.title);
      });

  void zoom(int i) => showDialog(
        context: context,
        builder: (c) => Dialog.fullscreen(
          backgroundColor: Colors.black87,
          child: Stack(children: [
            Positioned.fill(child: InteractiveViewer(maxScale: 8, child: Center(child: FittedBox(fit: BoxFit.fitWidth, child: Sheet(spec: widget.spec, no: i + 1, count: widget.spec.bodies.length))))),
            Positioned(top: 8, right: 8, child: SafeArea(child: IconButton(color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c)))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final n = widget.spec.bodies.length;
    return Scaffold(
      appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: Text(widget.spec.title)),
      body: Column(children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
          for (var i = 0; i < n; i++)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: GestureDetector(
              onTap: () => zoom(i),
              child: Card(clipBehavior: Clip.antiAlias, elevation: 3, margin: EdgeInsets.zero, child: FittedBox(
                fit: BoxFit.fitWidth,
                child: RepaintBoundary(key: keys[i], child: Sheet(spec: widget.spec, no: i + 1, count: n))))),
            ),
        ]))),
        SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          Expanded(child: FilledButton.icon(onPressed: busy ? null : sharePdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('مشاركة / حفظ PDF'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: busy ? null : shareImages, icon: const Icon(Icons.image_outlined), label: const Text('كصور'))),
        ]))),
      ]),
    );
  }
}

// ───────────── تبويب التقارير ─────────────

Future<T?> pick<T>(BuildContext c, String title, List<(String, T)> items) => showModalBottomSheet<T>(
      context: c, isScrollControlled: true,
      builder: (ctx) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(14), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        Flexible(child: ListView(shrinkWrap: true, children: [for (final it in items) ListTile(title: Text(it.$1), onTap: () => Navigator.pop(ctx, it.$2))])),
      ]))),
    );

class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  Widget item(IconData ic, String t, String sub, VoidCallback f) => Card(color: Colors.white, child: ListTile(
        leading: CircleAvatar(backgroundColor: green, foregroundColor: Colors.white, child: Icon(ic)),
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_left), onTap: f));

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [statCard('إجمالي الإيرادات', store.income, green), statCard('المصروفات', store.spent, red), statCard('الرصيد', store.balance, gold)]),
        const Padding(padding: EdgeInsets.fromLTRB(6, 8, 6, 6), child: Text('إصدار التقارير (PDF)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        item(Icons.table_chart, 'التقرير الشامل', 'كل الأشهر والأعضاء مع الإجماليات', () => openReport(context, comprehensiveReport())),
        item(Icons.calendar_month, 'تقرير شهري', 'من سدّد ومن لم يسدّد في شهر محدد', () async {
          final mk = await pick<String>(context, 'اختر الشهر', [for (final k in store.months.cast<String>().reversed) (mLabel(k), k)]);
          if (mk != null && context.mounted) openReport(context, monthlyReport(mk));
        }),
        item(Icons.person, 'كشف حساب عضو', 'مدفوعات عضو ومتأخراته', () async {
          final m = await pick<Map>(context, 'اختر العضو', [for (final m in store.members.cast<Map>()) ('${m['name']}', m)]);
          if (m != null && context.mounted) openReport(context, memberReport(m));
        }),
        item(Icons.warning_amber, 'تقرير المتأخرات', 'الأعضاء غير المسدّدين للأشهر المستحقة', () => openReport(context, arrearsReport())),
        item(Icons.payments, 'تقرير المصروفات', 'تفاصيل المصروفات والسحبيات', () => openReport(context, expensesReport())),
      ]);
}
