enum Sky { valley, moon, garden, ember, ice, stars }

enum Course {
  valley('মেঘের উপত্যকা', '', Sky.valley, 0xffffdc86),
  gardens(
    'ঝুলন্ত বাগান',
    'সিঁড়ির মতো উঠুন, তারপর ধাপে ধাপে নামুন।',
    Sky.garden,
    0xffadf39f,
  ),
  bells('ঘণ্টার মিনার', 'ঘণ্টার তালে ফাঁক ছোট-বড় হয়।', Sky.moon, 0xffe8caff),
  twins(
    'যমজ গিরিপথ',
    'ফটকের মাঝের পাথর এড়িয়ে দুটির এক পথ ধরুন।',
    Sky.ice,
    0xff8beaff,
  ),
  forge(
    'অঙ্গার দুর্গ',
    'বুস্ট ধরে রাখলে সোনালি ফটক খুলে যায়।',
    Sky.ember,
    0xffffb366,
  ),
  slalom(
    'বরফের বাঁক',
    'এক গেট উঁচু, পরেরটা নিচু। ছন্দ ধরে বাঁক নিন।',
    Sky.ice,
    0xffc9f8ff,
  ),
  comet(
    'ধূমকেতুর বন্দর',
    'লেজওয়ালা পালকটা ফাঁকের ভেতর ছুটে বেড়ায়।',
    Sky.stars,
    0xffffc8ef,
  ),
  tide(
    'জোয়ারের মন্দির',
    'ফাঁকগুলো ঢেউয়ের মতো দোলে। ঢেউয়ের সঙ্গে উড়ুন।',
    Sky.garden,
    0xff91ffda,
  ),
  echo(
    'প্রতিধ্বনি গুহা',
    'জোড়া গেট একই উচ্চতায়। দুটো পেরিয়ে বাঁক নিন।',
    Sky.ice,
    0xffbcb6ff,
  ),
  lantern(
    'জোনাকির নদী',
    'ফাঁকে আগুনগোলা দোলে। পালকের পাশ দিয়ে উড়ুন।',
    Sky.garden,
    0xfff5ec88,
  ),
  pistons(
    'লাভার চুল্লি',
    'চলন্ত ফটক একবার ওপরে, একবার নিচে মুখ বন্ধ করে।',
    Sky.ember,
    0xffff936d,
  ),
  weave(
    'স্ফটিকের গোলকধাঁধা',
    'চওড়া পথ পাল্টায়। পালক সরু পথে ডাকবে।',
    Sky.ice,
    0xffaaf7ff,
  ),
  ribbon(
    'মেরু এক্সপ্রেস',
    'তিনটি কাছাকাছি তোরণ পেরিয়ে লম্বা মোড় নিন।',
    Sky.moon,
    0xffb3caff,
  ),
  orbit(
    'নক্ষত্র কক্ষপথ',
    'নক্ষত্রটা ঘুরছে। বাইরের পালক ধরে পাশ কাটান।',
    Sky.stars,
    0xffe9bcff,
  ),
  relay(
    'সূর্য রিলে',
    'বুস্টে ফটক খুলুন, তারপর দুই পথের একটা বাছুন।',
    Sky.ember,
    0xffffd679,
  ),
  crown(
    'আকাশের মুকুট',
    'চার গেট পরপর খেলার নিয়ম বদলায়। ফটকের চিহ্ন দেখুন।',
    Sky.stars,
    0xffffde94,
  );

  const Course(this.title, this.hint, this.sky, this.accent);
  final String title, hint;
  final Sky sky;
  final int accent;
  int get level => index == 0 ? 1 : index * 5;
  static Course at(int level) =>
      values[(level ~/ 5).clamp(0, values.length - 1)];
}

enum GateStyle { arch, iris, fork, boostLock, comet, sentry, orbit }
