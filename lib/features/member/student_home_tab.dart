import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/firestore_keys.dart';
import 'student_job_detail_page.dart';

// 학생 대시보드 홈 탭
// 구성: 인사말 헤더 → 임시PW 경고 → 퀵 통계 → 공지 롤링 → 구직 무한스크롤 목록
class StudentHomeTab extends StatefulWidget {
  final String userName;
  final VoidCallback onViewApplications;
  const StudentHomeTab({
    super.key,
    required this.userName,
    required this.onViewApplications,
  });

  @override
  State<StudentHomeTab> createState() => _StudentHomeTabState();
}

class _StudentHomeTabState extends State<StudentHomeTab> {
  static const int _pageSize = 15;

  final _db         = FirebaseFirestore.instance;
  final _scrollCtrl = ScrollController();
  final _pageCtrl   = PageController();
  Timer? _bannerTimer;

  // 사용자 정보
  String _courseName = '';
  bool   _isTempPw  = false;

  // 지원 통계
  int _statPending  = 0;
  int _statApproved = 0;

  // 공지 롤링
  List<QueryDocumentSnapshot> _notices     = [];
  int                          _bannerIndex = 0;

  // 구직 무한스크롤
  List<QueryDocumentSnapshot> _jobs       = [];
  DocumentSnapshot?            _lastJobDoc;
  bool _hasMore     = true;
  bool _loadingJobs = false;

  bool _initialLoading = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadAll();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _pageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // 스크롤 끝 근접 시 다음 페이지 로드
  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadJobs();
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadUserInfo(), _loadStats(), _loadNotices()]);
    await _loadJobs();
    if (mounted) setState(() => _initialLoading = false);
  }

  // users 문서에서 소속 반 + 임시PW 여부
  Future<void> _loadUserInfo() async {
    final userSnap = await _db.collection(FsCol.users).doc(_uid).get();
    final data     = userSnap.data();
    if (data == null) return;

    _isTempPw = data[FsUser.isTempPw] as bool? ?? false;
    final courseId = data[FsUser.courseId] as String? ?? '';
    if (courseId.isNotEmpty) {
      final courseSnap =
          await _db.collection(FsCol.courses).doc(courseId).get();
      _courseName = courseSnap.data()?[FsCourse.name] as String? ?? '';
    }
  }

  // 구직 지원 현황 — 대기/승인 건수
  Future<void> _loadStats() async {
    final results = await Future.wait([
      _db
          .collection(FsCol.jobApplications)
          .where(FsJobApp.applicantId, isEqualTo: _uid)
          .where(FsJobApp.status, isEqualTo: FsJobApp.statusPending)
          .get(),
      _db
          .collection(FsCol.jobApplications)
          .where(FsJobApp.applicantId, isEqualTo: _uid)
          .where(FsJobApp.status, isEqualTo: FsJobApp.statusApproved)
          .get(),
    ]);
    if (!mounted) return;
    _statPending  = results[0].docs.length;
    _statApproved = results[1].docs.length;
  }

  // 최신 공지 5건 (소프트 삭제 제외)
  Future<void> _loadNotices() async {
    final snap = await _db
        .collection(FsCol.notices)
        .orderBy(FsNotice.createdAt, descending: true)
        .limit(20)
        .get();
    if (!mounted) return;
    _notices = snap.docs
        .where((d) => !((d.data()[FsNotice.isDeleted] as bool?) ?? false))
        .take(5)
        .toList();
    if (_notices.length > 1) _startBannerTimer();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _notices.isEmpty) return;
      final next = (_bannerIndex + 1) % _notices.length;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut);
    });
  }

  // 구직 목록 15개 단위 무한스크롤 로드
  Future<void> _loadJobs() async {
    if (_loadingJobs || !_hasMore) return;
    setState(() => _loadingJobs = true);
    try {
      var query = _db
          .collection(FsCol.jobs)
          .orderBy(FsJob.createdAt, descending: true)
          .limit(_pageSize);
      if (_lastJobDoc != null) {
        query = query.startAfterDocument(_lastJobDoc!);
      }
      final snap = await query.get();
      if (!mounted) return;
      final newDocs = snap.docs.where((d) {
        return !((d.data()[FsJob.isDeleted] as bool?) ?? false);
      }).toList();
      setState(() {
        _jobs.addAll(newDocs);
        if (snap.docs.isNotEmpty) _lastJobDoc = snap.docs.last;
        _hasMore   = snap.docs.length == _pageSize;
        _loadingJobs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingJobs = false);
    }
  }

  Future<void> _refresh() async {
    _bannerTimer?.cancel();
    setState(() {
      _jobs.clear();
      _lastJobDoc = null;
      _hasMore    = true;
      _initialLoading = true;
    });
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ① 인사말 헤더 카드
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildHeaderCard(),
            ),
          ),

          // ② 임시PW 경고 배너
          if (_isTempPw)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildTempPwBanner(),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // ③ 퀵 통계 카드
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildStatsRow(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ④ 공지사항 롤링 배너
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('공지사항'),
                  const SizedBox(height: 10),
                  _notices.isEmpty
                      ? _buildEmptyCard('등록된 공지사항이 없습니다.')
                      : _buildNoticeBanner(),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ⑤ 구직 공고 섹션 타이틀
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildSectionTitle('구직 공고'),
                  const SizedBox(width: 8),
                  Text('(${_jobs.length}건)',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 10)),

          // ⑥ 구직 공고 리스트
          if (_jobs.isEmpty && !_loadingJobs)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildEmptyCard('등록된 구직 공고가 없습니다.'),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _JobListItem(
                    key: ValueKey(_jobs[i].id), // 👈 새로 추가: 문서의 고유 ID를 Key로 할당합니다.
                    doc: _jobs[i],
                    index: i + 1,
                    onTap: () => _openDetail(_jobs[i]),
                  ),
                ),
                childCount: _jobs.length,
              ),
            ),

          // ⑦ 로딩 / 끝 표시
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: _loadingJobs
                  ? const Center(child: CircularProgressIndicator())
                  : !_hasMore && _jobs.isNotEmpty
                      ? const Center(
                          child: Text('모든 공고를 불러왔습니다.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)))
                      : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(QueryDocumentSnapshot doc) {
    // 👈 플러터 웹의 마우스 추적기 충돌 버그를 우회하기 위해,
    // MaterialPageRoute 대신 PageRouteBuilder를 사용하여 애니메이션 시간을 '0'으로 만듭니다.
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => StudentJobDetailPage(
          jobDoc: doc,
          currentUid: _uid,
        ),
        transitionDuration: Duration.zero, // 화면 진입 애니메이션 제거
        reverseTransitionDuration: Duration.zero, // 화면 뒤로 가기 애니메이션 제거
      ),
    );
  }
  // ── 위젯 빌더 ──────────────────────────────────────────

  Widget _buildHeaderCard() {
    final course = _courseName.isEmpty ? '반 미배정' : _courseName;
    return Semantics(
      label: '소속 반 $course, ${widget.userName}님. 마이페이지로 이동합니다.',
      button: true,
      child: GestureDetector(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('마이페이지는 준비 중입니다.'),
              duration: Duration(seconds: 2)),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.userName} 님 환영합니다.',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.3),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTempPwBanner() {
    return Semantics(
      label: '임시 비밀번호 변경 안내입니다. 비밀번호를 변경해 주세요.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB300), width: 1.2),
        ),
        child: Row(
          children: const [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFE65100), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '임시 비밀번호를 사용 중입니다. 마이페이지에서 비밀번호를 변경해 주세요.',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFFE65100), height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _QuickStatCard(
            icon: Icons.hourglass_top_rounded,
            iconColor: const Color(0xFFEF6C00),
            bgColor: const Color(0xFFFFF3E0),
            label: '지원 대기',
            count: _statPending,
            onTap: widget.onViewApplications,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickStatCard(
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF2E7D32),
            bgColor: const Color(0xFFE8F5E9),
            label: '지원 승인',
            count: _statApproved,
            onTap: widget.onViewApplications,
          ),
        ),
      ],
    );
  }

  Widget _buildNoticeBanner() {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.18), width: 1),
      ),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: _notices.length,
            onPageChanged: (i) => setState(() => _bannerIndex = i),
            itemBuilder: (_, i) {
              final title =
                  ((_notices[i].data() as Map<String, dynamic>)[FsNotice.title] as String?) ?? '-';
              return Semantics(
                label: '공지사항 ${i + 1}번: $title',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('공지',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _notices.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _bannerIndex == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _bannerIndex == i
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Text(
        title,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
      );

  Widget _buildEmptyCard(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Center(
          child: Text(message,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
        ),
      );
}

// ─────────────────────────────────────────────────────────
// 구직 공고 리스트 아이템 — 순번·제목·첨부아이콘·조회수
// ─────────────────────────────────────────────────────────
class _JobListItem extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final int index;
  final VoidCallback onTap;
  const _JobListItem(
      {super.key, required this.doc, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data        = doc.data() as Map<String, dynamic>;
    final title       = data[FsJob.title]       as String? ?? '-';
    final authorName  = data[FsJob.authorName]  as String? ?? '-';
    final period      = data[FsJob.period]       as String? ?? '-';
    // final attachments = data[FsJob.attachments]  as List?   ?? []; // 차후 개발
    final viewCount   = data[FsJob.viewCount]    as int?    ?? 0;
    // final hasAttach   = attachments.isNotEmpty; // 차후 개발

    return Semantics(
      label: '$index번 $title, $authorName 등록, 기간 $period, 조회 $viewCount회',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              // 순번
              SizedBox(
                width: 32,
                child: Text('$index',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFBDBDBD))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목 + 첨부파일 아이콘
                    Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        // 차후 개발: 첨부파일 아이콘
                        // if (hasAttach) ...[
                        //   const SizedBox(width: 4),
                        //   const Icon(Icons.attach_file_rounded,
                        //       size: 14, color: AppColors.textSecondary),
                        // ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 등록자·기간·조회수
                    Row(
                      children: [
                        Expanded(
                          child: Text('$authorName · $period',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.visibility_rounded,
                                size: 13, color: Color(0xFF9E9E9E)),
                            const SizedBox(width: 2),
                            Text('$viewCount',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF9E9E9E))),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF9E9E9E), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// 퀵 통계 아이콘 카드
class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final Color    bgColor;
  final String   label;
  final int      count;
  final VoidCallback onTap;
  const _QuickStatCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $count건. 탭하면 내 지원 탭으로 이동합니다.',
      button: true,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('$count건',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
