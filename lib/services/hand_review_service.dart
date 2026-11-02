import 'dart:convert';
import 'dart:io';
import '../models/hand.dart';
import '../engine/deal_generator.dart';
import '../engine/auction_engine.dart';
import 'board_exporter.dart';
import 'hand_parser.dart';

/// Represents a bridge board saved for review.
class ReviewBoard {
  final String id;
  final String filename;
  final String filePath;
  final String shortDescription;
  final String longDescription;
  final PartnershipDeal deal;
  final String dealer; // 'N', 'E', 'S', 'W'
  final String vulnerable; // 'None', 'NS', 'EW', 'All'
  final String systemName;
  final DateTime savedAt;
  final List<String> originalAuctionCalls;
  final String? errorType;
  final bool isFixed;

  const ReviewBoard({
    required this.id,
    required this.filename,
    required this.filePath,
    required this.shortDescription,
    required this.longDescription,
    required this.deal,
    required this.dealer,
    required this.vulnerable,
    required this.systemName,
    required this.savedAt,
    this.originalAuctionCalls = const [],
    this.errorType,
    this.isFixed = false,
  });

  /// Returns a clean display title for the board list.
  String get displayTitle => shortDescription.isNotEmpty ? shortDescription : filename;
}

/// Service for persisting, listing, loading, and deleting review hands in PBN format
/// in the `review/` directory.
class HandReviewService {
  final Directory reviewDirectory;

  HandReviewService({Directory? directory})
      : reviewDirectory = directory ?? Directory('errors');

  /// Ensures that the review directory exists on disk.
  Future<Directory> ensureReviewDirectory() async {
    if (!await reviewDirectory.exists()) {
      return await reviewDirectory.create(recursive: true);
    }
    return reviewDirectory;
  }

  /// Sanitizes a string to make it safe for filenames.
  static String sanitizeFilename(String input) {
    var sanitized = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .trim()
        .replaceAll(RegExp(r'[\s\-]+'), '_');
    if (sanitized.length > 40) {
      sanitized = sanitized.substring(0, 40);
    }
    return sanitized.isEmpty ? 'hand' : sanitized;
  }

  /// Formats a DateTime for PBN tag (YYYY.MM.DD).
  static String formatPbnDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y.$m.$d';
  }

  /// Formats a DateTime for filename timestamp (YYYYMMDD_HHmmss).
  static String formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '${y}${m}${d}_${hh}${mm}${ss}';
  }

  /// Default error categories for bidding failures.
  static const List<String> defaultCategories = [
    'Wrong Bid',
    'Premature Pass',
    'Wrong Opening Bid',
    'Wrong Strain / Fit Missed',
    'Forcing State Broken',
    'Slam Bidding Error',
    'Overbidding / Misvaluation',
    'Unrecognized Convention',
    'Opposition Defense Error',
    'Other',
  ];

  File get _categoriesFile => File('${reviewDirectory.path}/categories.json');

  /// Retrieves all categories, including user-defined categories persisted in categories.json.
  Future<List<String>> getCategories() async {
    try {
      if (await _categoriesFile.exists()) {
        final content = await _categoriesFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        final categories = list.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
        categories.addAll(defaultCategories);
        return categories.toList();
      }
    } catch (_) {}
    return List<String>.from(defaultCategories);
  }

  /// Adds a new category to categories.json if it is not already present.
  Future<void> addCategory(String category) async {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return;
    await ensureReviewDirectory();
    final existing = await getCategories();
    if (!existing.contains(trimmed)) {
      existing.add(trimmed);
      await _categoriesFile.writeAsString(jsonEncode(existing));
    }
  }

  /// Saves a hand to disk in the review directory in PBN format.
  /// Returns the saved [File].
  Future<File> saveBoard({
    required PartnershipDeal deal,
    required String dealer,
    required String shortDescription,
    required String longDescription,
    List<AuctionEntry> history = const [],
    String vulnerable = 'None',
    String systemName = 'Gavin Wolpert 2/1 GF',
    String? errorType,
    bool isFixed = false,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    await ensureReviewDirectory();

    if (errorType != null && errorType.trim().isNotEmpty) {
      await addCategory(errorType.trim());
    }

    final slug = sanitizeFilename(shortDescription);
    final filename = '${formatTimestamp(now)}_$slug.pbn';
    final filePath = '${reviewDirectory.path}/$filename';
    final file = File(filePath);

    final pbnContent = BoardExporter.exportToPbn(
      deal: deal,
      history: history,
      options: BoardExportOptions(
        dealer: dealer,
        vulnerable: vulnerable,
        date: formatPbnDate(now),
        systemName: systemName,
        shortDescription: shortDescription,
        longDescription: longDescription,
        errorType: errorType,
        isFixed: isFixed,
      ),
    );

    await file.writeAsString(pbnContent);
    return file;
  }

  /// Lists all review boards currently stored in the review directory, sorted newest first.
  Future<List<ReviewBoard>> listReviewBoards() async {
    if (!await reviewDirectory.exists()) {
      return [];
    }

    final entities = await reviewDirectory.list().toList();
    final boards = <ReviewBoard>[];

    for (final entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.pbn')) {
        try {
          final content = await entity.readAsString();
          final basename = entity.uri.pathSegments.last;
          final board = parsePbn(
            content,
            filename: basename,
            filePath: entity.path,
          );
          boards.add(board);
        } catch (_) {
          // Ignore invalid or unparseable files
        }
      }
    }

    boards.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return boards;
  }

  /// Loads a single review board by its filename.
  Future<ReviewBoard?> loadBoard(String filename) async {
    final file = File('${reviewDirectory.path}/$filename');
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    return parsePbn(
      content,
      filename: filename,
      filePath: file.path,
    );
  }

  /// Updates the fixed status of a board in the review directory.
  Future<bool> updateBoardFixedStatus(String filename, bool isFixed) async {
    final file = File('${reviewDirectory.path}/$filename');
    if (!await file.exists()) return false;
    final content = await file.readAsString();
    final fixedRegex = RegExp(r'\[Fixed\s+"[^"]*"\]', caseSensitive: false);
    String updated;
    if (fixedRegex.hasMatch(content)) {
      updated = content.replaceAll(fixedRegex, '[Fixed "${isFixed ? 'Yes' : 'No'}"]');
    } else {
      final descRegex = RegExp(r'(\[Description\s+"[^"]*"\])', caseSensitive: false);
      if (descRegex.hasMatch(content)) {
        updated = content.replaceFirst(descRegex, '\$1\n[Fixed "${isFixed ? 'Yes' : 'No'}"]');
      } else {
        updated = '[Fixed "${isFixed ? 'Yes' : 'No'}"]\n$content';
      }
    }
    await file.writeAsString(updated);
    return true;
  }

  /// Updates details (category, descriptions, fixed status) of a board.
  Future<bool> updateBoardDetails(
    String filename, {
    String? shortDescription,
    String? longDescription,
    String? errorType,
    bool? isFixed,
  }) async {
    final file = File('${reviewDirectory.path}/$filename');
    if (!await file.exists()) return false;
    var content = await file.readAsString();

    if (errorType != null && errorType.trim().isNotEmpty) {
      final err = errorType.trim();
      await addCategory(err);
      final errorRegex = RegExp(r'\[ErrorType\s+"[^"]*"\]', caseSensitive: false);
      if (errorRegex.hasMatch(content)) {
        content = content.replaceAll(errorRegex, '[ErrorType "$err"]');
      } else {
        content = content.replaceFirst(RegExp(r'(\[Description\s+"[^"]*"\])'), '\$1\n[ErrorType "$err"]');
      }
    }

    if (isFixed != null) {
      final fixedRegex = RegExp(r'\[Fixed\s+"[^"]*"\]', caseSensitive: false);
      if (fixedRegex.hasMatch(content)) {
        content = content.replaceAll(fixedRegex, '[Fixed "${isFixed ? 'Yes' : 'No'}"]');
      } else {
        content = content.replaceFirst(RegExp(r'(\[Description\s+"[^"]*"\])'), '\$1\n[Fixed "${isFixed ? 'Yes' : 'No'}"]');
      }
    }

    if (shortDescription != null && shortDescription.trim().isNotEmpty) {
      final sanitizedShort = shortDescription.replaceAll('"', "''").replaceAll('\n', ' ').trim();
      final descRegex = RegExp(r'\[Description\s+"[^"]*"\]', caseSensitive: false);
      if (descRegex.hasMatch(content)) {
        content = content.replaceAll(descRegex, '[Description "$sanitizedShort"]');
      }
    }

    if (longDescription != null) {
      final sanitizedLong = longDescription.trim();
      final braceRegex = RegExp(r'\{[\s\S]*?\}');
      final newBrace = '{\n  ${sanitizedLong.split('\n').join('\n  ')}\n}';
      if (braceRegex.hasMatch(content)) {
        content = content.replaceFirst(braceRegex, newBrace);
      }
      final commentRegex = RegExp(r'\[Comment\s+"[^"]*"\]', caseSensitive: false);
      final sanitizedComment = sanitizedLong.replaceAll('"', "''").replaceAll('\n', ' ').trim();
      if (commentRegex.hasMatch(content)) {
        content = content.replaceAll(commentRegex, '[Comment "$sanitizedComment"]');
      }
    }

    await file.writeAsString(content);
    return true;
  }

  /// Deletes a review board file.
  Future<bool> deleteBoard(String filename) async {
    final file = File('${reviewDirectory.path}/$filename');
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// Parses PBN content into a [ReviewBoard].
  ReviewBoard parsePbn(
    String pbnContent, {
    String filename = '',
    String filePath = '',
  }) {
    // 1. Short Description ([Description "..."])
    final descMatch = RegExp(r'\[Description\s+"([^"]*)"\]', caseSensitive: false).firstMatch(pbnContent);
    String shortDesc = descMatch?.group(1)?.trim() ?? '';

    // 2. Long Description: Prefer brace block { ... }, fallback to [Comment "..."]
    final braceMatch = RegExp(r'\{([\s\S]*?)\}').firstMatch(pbnContent);
    String longDesc = '';
    if (braceMatch != null) {
      longDesc = braceMatch.group(1)!.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n');
    } else {
      final commentMatch = RegExp(r'\[Comment\s+"([^"]*)"\]', caseSensitive: false).firstMatch(pbnContent);
      if (commentMatch != null) {
        longDesc = commentMatch.group(1)!.trim();
      }
    }

    // Fallback title from filename if short description is empty
    if (shortDesc.isEmpty && filename.isNotEmpty) {
      var raw = filename.replaceAll(RegExp(r'\.pbn$', caseSensitive: false), '');
      // Remove timestamp prefix if present
      raw = raw.replaceFirst(RegExp(r'^\d{8}_\d{6}_'), '');
      shortDesc = raw.replaceAll('_', ' ');
    }

    // 3. Dealer ([Dealer "N|E|S|W"])
    final dealerMatch = RegExp(r'\[Dealer\s+"([NSEW])"\]', caseSensitive: false).firstMatch(pbnContent);
    final dealer = dealerMatch?.group(1)?.toUpperCase() ?? 'N';

    // 4. Vulnerable ([Vulnerable "..."])
    final vulnMatch = RegExp(r'\[Vulnerable\s+"([^"]*)"\]', caseSensitive: false).firstMatch(pbnContent);
    final vulnerable = vulnMatch?.group(1)?.trim() ?? 'None';

    // 5. BiddingSystem ([BiddingSystem "..."])
    final sysMatch = RegExp(r'\[BiddingSystem\s+"([^"]*)"\]', caseSensitive: false).firstMatch(pbnContent);
    final systemName = sysMatch?.group(1)?.trim() ?? 'Gavin Wolpert 2/1 GF';

    // 6. Date / savedAt ([Date "YYYY.MM.DD"])
    final dateMatch = RegExp(r'\[Date\s+"([^"]*)"\]', caseSensitive: false).firstMatch(pbnContent);
    DateTime savedAt = DateTime.now();
    if (dateMatch != null) {
      final parts = dateMatch.group(1)!.split('.');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          savedAt = DateTime(y, m, d);
        }
      }
    }

    // 7. Deal hands ([Deal "N:..."])
    final handsMap = HandParser.parseDealText(pbnContent);
    final deal = HandParser.completeDeal(handsMap);

    // 8. Auction calls ([Auction "N"] ...)
    final List<String> auctionCalls = [];
    final auctionMatch = RegExp(r'\[Auction\s+"[NSEW]"\]([\s\S]*?)(?:\[|$)', caseSensitive: false).firstMatch(pbnContent);
    if (auctionMatch != null) {
      final body = auctionMatch.group(1)!;
      for (final line in body.split('\n')) {
        final clean = line.replaceAll(RegExp(r'\{.*?\}'), '').trim();
        if (clean.isNotEmpty && !clean.startsWith('[')) {
          auctionCalls.addAll(clean.split(RegExp(r'\s+')).where((c) => c.isNotEmpty));
        }
      }
    }

    // 9. ErrorType and Fixed status
    final errorTypeMatch = RegExp(r'\[ErrorType\s+"([^"]*)"\]', caseSensitive: false).firstMatch(pbnContent);
    final errorType = errorTypeMatch?.group(1)?.trim();

    final fixedMatch = RegExp(r'\[Fixed\s+"([^"]*)"\]', caseSensitive: false).firstMatch(pbnContent);
    final fixedVal = fixedMatch?.group(1)?.trim().toLowerCase();
    final isFixed = fixedVal == 'yes' || fixedVal == 'true';

    return ReviewBoard(
      id: filename.isNotEmpty ? filename : shortDesc,
      filename: filename,
      filePath: filePath,
      shortDescription: shortDesc,
      longDescription: longDesc,
      deal: deal,
      dealer: dealer,
      vulnerable: vulnerable,
      systemName: systemName,
      savedAt: savedAt,
      originalAuctionCalls: auctionCalls,
      errorType: errorType,
      isFixed: isFixed,
    );
  }
}
