// 관리자 대시보드 메인 페이지입니다.
// cc.png 디자인 기준: 좌측 파란 사이드바 + 우측 콘텐츠 영역 구조입니다.
//
// 접근 권한:
//   - SUPER_ADMIN: 회원관리(전체), 강좌관리, 공지사항관리, 구직등록관리
//   - INSTRUCTOR : 회원관리(내 반 학생 승인/거절만), 공지사항관리, 구직등록관리
//
// Firestore: users/{uid} 의 role 필드로 메뉴 항목을 분기합니다.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/enums/user_role.dart';
import '../../core/utils/firestore_keys.dart';
import '../instructor/instructor_profile_page.dart';
import 'tabs/home_tab.dart';
import 'tabs/instructor_home_tab.dart';
import 'tabs/member_tab.dart';
import 'tabs/course_tab.dart';
import 'tabs/notice_tab.dart';
import 'tabs/job_tab.dart';
import '../login/login_intro_page.dart';

// 관리자 대시보드 페이지 — 사이드바 + 콘텐츠 영역을 포함합니다.
// 화면 상태(현재 선택된 메뉴)가 바뀌므로 StatefulWidget으로 구현합니다.
class AdminDashboardPage extends StatefulWidget {
  // 현재 로그인한 사용자의 역할을 외부에서 주입받습니다.
  final UserRole userRole;

  // 현재 로그인한 사용자의 이름입니다.
  final String userName;

  const AdminDashboardPage({
    super.key,
    required this.userRole,
    required this.userName,
  });

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // ── 디자인 상수 (cc.png 기준) ─────────────────────────────
  // 사이드바 배경 파란색
  static const Color _sidebarBg = Color(0xFF1565C0);
  // 사이드바 활성 메뉴 배경 (조금 밝은 파랑)
  static const Color _sidebarActive = Color(0xFF1976D2);
  // 사이드바 텍스트/아이콘 기본색 (연한 흰색)
  static const Color _sidebarText = Color(0xFFBBDEFB);
  // 사이드바 텍스트/아이콘 활성색 (흰색)
  static const Color _sidebarTextActive = Colors.white;
  // 사이드바 고정 너비
  static const double _sidebarWidth = 220;

  // 현재 선택된 메뉴 인덱스 (0 = 홈 대시보드)
  int _selectedIndex = 0;

  // INSTRUCTOR 프로필 사진 URL
  String _instructorPhotoUrl = '';

  @override
  void initState() {
    super.initState();
    if (widget.userRole == UserRole.INSTRUCTOR) _loadInstructorPhoto();
  }

  // INSTRUCTOR 프로필 사진 Firestore 로드
  Future<void> _loadInstructorPhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection(FsCol.users)
        .doc(uid)
        .get();
    if (!mounted) return;
    setState(() {
      _instructorPhotoUrl =
          (doc.data()?[FsUser.photoUrl] as String?) ?? '';
    });
  }

  void _goToProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InstructorProfilePage()),
    ).then((_) {
      // 마이페이지에서 사진 변경 후 돌아오면 갱신
      if (widget.userRole == UserRole.INSTRUCTOR) _loadInstructorPhoto();
    });
  }

  // ── 메뉴 항목 정의 ────────────────────────────────────────
  // 역할에 따라 보이는 메뉴가 달라집니다. (INSTRUCTOR는 강좌관리 숨김)
  List<_MenuItem> get _menuItems {
    return [
      _MenuItem(icon: Icons.dashboard_rounded, label: '관리 대시보드'),
      
      // 👇 이 부분이 변경되었습니다! 
      // 최고 관리자(SUPER_ADMIN)로 로그인한 경우 '교사 관리'로 표시하고, 
      // 교사(INSTRUCTOR)로 로그인한 경우에는 기존대로 '회원 관리'로 표시합니다.
      _MenuItem(
        icon: Icons.people_alt_rounded, 
        label: widget.userRole == UserRole.SUPER_ADMIN ? '교사/학생 관리' : '학생 관리',
      ),
      
      if (widget.userRole == UserRole.SUPER_ADMIN)
        _MenuItem(icon: Icons.school_rounded, label: '강좌 관리'),
      
      _MenuItem(icon: Icons.campaign_rounded, label: '공지사항 관리'),
      
      // INSTRUCTOR 전용 — 구직 등록
      if (widget.userRole == UserRole.INSTRUCTOR)
        _MenuItem(icon: Icons.work_rounded, label: '구직 등록 관리'),
    ];
  }

  // 현재 선택된 인덱스에 해당하는 콘텐츠 탭을 반환합니다.
  Widget _buildContent() {
    // SUPER_ADMIN과 INSTRUCTOR의 메뉴 인덱스 매핑이 다르므로 분기합니다.
    if (widget.userRole == UserRole.SUPER_ADMIN) {
      // SUPER_ADMIN: 홈(0), 회원(1), 강좌(2), 공지(3)
      switch (_selectedIndex) {
        case 0: return const HomeTab();
        case 1: return MemberTab(userRole: widget.userRole);
        case 2: return const CourseTab();
        case 3: return NoticeTab(userRole: widget.userRole, userName: widget.userName);
        default: return const HomeTab();
      }
    } else {
      // INSTRUCTOR: 홈(0), 회원(1), 공지(2), 구직(3)
      switch (_selectedIndex) {
        case 0: return const InstructorHomeTab();
        case 1: return MemberTab(userRole: widget.userRole);
        case 2: return NoticeTab(userRole: widget.userRole, userName: widget.userName);
        case 3: return JobTab(userRole: widget.userRole, userName: widget.userName);
        default: return const HomeTab();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 화면 너비로 모바일 여부를 판단합니다.
    // 600px 미만: 모바일(Drawer 방식), 이상: 데스크톱/태블릿(고정 사이드바)
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA), // 연한 회색 콘텐츠 배경
      drawer: isMobile ? _buildDrawer() : null,
      appBar: isMobile ? _buildMobileAppBar() : null,
      body: isMobile
          // 모바일: 콘텐츠만 표시, 사이드바는 Drawer로
          ? _buildContent()
          // 태블릿/웹: 좌측 사이드바 + 우측 콘텐츠 나란히 배치
          : Row(
              children: [
                _buildSidebar(),
                Expanded(child: _buildContent()),
              ],
            ),
    );
  }

  // 모바일용 AppBar — 햄버거 메뉴 + 타이틀 + INSTRUCTOR 아바타
  AppBar _buildMobileAppBar() {
    return AppBar(
      backgroundColor: _sidebarBg,
      foregroundColor: Colors.white,
      title: const Text(
        'Job 알리미 관리',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      elevation: 0,
      actions: widget.userRole == UserRole.INSTRUCTOR
          ? [
              Semantics(
                label: '내 프로필 보기 버튼',
                button: true,
                child: GestureDetector(
                  onTap: () => _goToProfile(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildAvatar(radius: 18),
                  ),
                ),
              ),
            ]
          : null,
    );
  }

  // 모바일용 Drawer
  Drawer _buildDrawer() {
    return Drawer(child: _buildSidebar(isDrawer: true));
  }

  // 좌측 사이드바 위젯
  // cc.png 기준: 파란 배경, 앱명, 사용자 정보, 메뉴 항목, 하단 로그아웃
  Widget _buildSidebar({bool isDrawer = false}) {
    return Container(
      width: isDrawer ? double.infinity : _sidebarWidth,
      color: _sidebarBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 앱 로고 + 이름 ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.accessibility_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Job 알리미',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white24, thickness: 1),

            // ── 로그인 사용자 정보 ─────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Semantics(
                label: '현재 로그인 사용자: ${widget.userName}, 역할: ${_roleLabel()}',
                child: widget.userRole == UserRole.INSTRUCTOR
                    ? _buildInstructorUserInfo()
                    : _buildDefaultUserInfo(),
              ),
            ),

            const Divider(color: Colors.white24, thickness: 1),
            const SizedBox(height: 8),

            // ── 메뉴 항목 목록 ─────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _menuItems.length,
                itemBuilder: (context, index) {
                  final item = _menuItems[index];
                  final bool isActive = _selectedIndex == index;
                  return Semantics(
                    label: '${item.label} 메뉴 버튼입니다.',
                    selected: isActive,
                    child: _buildMenuTile(item, index, isActive),
                  );
                },
              ),
            ),

            const Divider(color: Colors.white24, thickness: 1),

            // ── 하단 로그아웃 버튼 ─────────────────────────
            Semantics(
              label: '로그아웃 버튼입니다. 누르면 로그인 화면으로 이동합니다.',
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.white70, size: 22),
                title: const Text('로그아웃', style: TextStyle(color: Colors.white70, fontSize: 14)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const LoginIntroPage()),
                    (_) => false,
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // INSTRUCTOR 사이드바 사용자 정보 (아바타 + 역할 + 이름, 클릭 시 마이페이지)
  Widget _buildInstructorUserInfo() {
    return GestureDetector(
      onTap: () => _goToProfile(context),
      child: Row(
        children: [
          _buildAvatar(radius: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '교사',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.userName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // SUPER_ADMIN 사이드바 사용자 정보 (기존 레이아웃)
  Widget _buildDefaultUserInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _roleLabel(),
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.userName,
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  // 프로필 CircleAvatar — DB 사진 있으면 NetworkImage, 없으면 기본 아이콘
  Widget _buildAvatar({required double radius}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withValues(alpha: 0.25),
      backgroundImage: _instructorPhotoUrl.isNotEmpty
          ? NetworkImage(_instructorPhotoUrl)
          : null,
      child: _instructorPhotoUrl.isEmpty
          ? Icon(Icons.person_rounded, color: Colors.white, size: radius)
          : null,
    );
  }

  // 개별 메뉴 항목 타일을 생성합니다.
  Widget _buildMenuTile(_MenuItem item, int index, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive ? _sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          item.icon,
          color: isActive ? _sidebarTextActive : _sidebarText,
          size: 22,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isActive ? _sidebarTextActive : _sidebarText,
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        onTap: () {
          setState(() => _selectedIndex = index);
          if (MediaQuery.of(context).size.width < 600) {
            Navigator.of(context).pop();
          }
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // UserRole Enum을 한글 레이블로 변환합니다.
  String _roleLabel() {
    switch (widget.userRole) {
      case UserRole.SUPER_ADMIN: return '최고 관리자';
      case UserRole.INSTRUCTOR:  return '교사';
      case UserRole.STUDENT:     return '학생';
    }
  }
}

// 사이드바 메뉴 항목 데이터 모델입니다.
class _MenuItem {
  final IconData icon;
  final String label;
  const _MenuItem({required this.icon, required this.label});
}
