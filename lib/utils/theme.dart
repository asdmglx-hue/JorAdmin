import 'package:flutter/material.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────
const kPurple      = Color(0xFF534AB7);
const kPurpleDeep  = Color(0xFF3D35A0);
const kPurpleLight = Color(0xFFEEEDFE);
const kPurpleMid   = Color(0xFFD4D1F7);
const kTeal        = Color(0xFF0F6E56);
const kTealLight   = Color(0xFFE1F5EE);
const kAmber       = Color(0xFFE8620A);
const kAmberLight  = Color(0xFFFEEDE3);
const kRose        = Color(0xFFE11D48);
const kRoseLight   = Color(0xFFFFE4E6);
const kInk         = Color(0xFF1A1830);
const kInkLight    = Color(0xFF6B6893);
const kInkFaint    = Color(0xFFB0ADCB);
const kSurface     = Color(0xFFFAF9FF);
const kCardBg      = Color(0xFFFFFFFF);
const kBorder      = Color(0xFFE8E6F5);
const kGreen       = Color(0xFF16A34A);
const kGreenLight  = Color(0xFFDCFCE7);
const kRed         = Color(0xFFDC2626);
const kRedLight    = Color(0xFFFEE2E2);

// ── Pakistani city list (grouped by province) ─────────────────────────────────
/// Flat list used for simple dropdowns / filter chips
const kCities = [
  // Punjab
  'Lahore','Faisalabad','Rawalpindi','Multan','Gujranwala','Sialkot','Bahawalpur',
  'Sargodha','Sheikhupura','Rahim Yar Khan','Jhelum','Gujrat','Okara','Sahiwal',
  'Khanewal','Vehari','Kasur','Dera Ghazi Khan','Layyah','Mianwali','Bhakkar',
  'Toba Tek Singh','Chiniot','Hafizabad','Lodhran','Muzaffargarh','Rajanpur',
  'Pakpattan','Narowal','Attock','Chakwal','Murree','Talagang','Fort Abbas',
  'Haroonabad','Hasilpur','Arifwala','Kallar Kahar','Mailsi','Kot Addu',
  'Kabirwala','Samundri','Phalia','Kharian','Wazirabad','Shorkot','Jampur',
  'Khanpur','Shakargarh','Daska','Kamoke',
  // Sindh
  'Karachi','Hyderabad','Sukkur','Larkana','Mirpur Khas','Khairpur','Nawabshah',
  'Badin','Thatta','Jamshoro','Sanghar','Ghotki','Jacobabad','Shikarpur','Dadu',
  'Umerkot','Tando Adam','Tando Allahyar','Sehwan Sharif','Shahdadkot','Mithi',
  'Kandhkot','Kotri','Mirwah','Matli','Khipro','Tharparkar',
  // Khyber Pakhtunkhwa
  'Peshawar','Mardan','Mingora','Abbottabad','Kohat','Dera Ismail Khan','Bannu',
  'Chitral','Mansehra','Haripur','Swabi','Nowshera','Charsadda','Batkhela',
  'Shangla','Hangu','Timergara','Dir Upper','Karak','Lakki Marwat','Tank',
  'Parachinar','Jamrud','Kohistan',
  // Balochistan
  'Quetta','Gwadar','Turbat','Khuzdar','Chaman','Sibi','Zhob','Hub',
  'Killa Saifullah','Dera Murad Jamali','Awaran','Panjgur','Kharan','Washuk',
  'Loralai','Mastung','Ziarat','Pasni','Ormara','Jaffarabad',
  // Islamabad
  'Islamabad',
  // Gilgit Baltistan
  'Gilgit','Skardu','Hunza','Chilas','Khaplu','Shigar','Astore','Nagar',
  // Azad Kashmir
  'Muzaffarabad','Mirpur','Rawalakot','Kotli','Bagh','Neelum Valley','Haveli',
  'Other',
];

/// Grouped map for searchable dropdowns (province → city list)
const kCitiesGrouped = <String, List<String>>{
  'Punjab': [
    'Lahore','Faisalabad','Rawalpindi','Multan','Gujranwala','Sialkot','Bahawalpur',
    'Sargodha','Sheikhupura','Rahim Yar Khan','Jhelum','Gujrat','Okara','Sahiwal',
    'Khanewal','Vehari','Kasur','Dera Ghazi Khan','Layyah','Mianwali','Bhakkar',
    'Toba Tek Singh','Chiniot','Hafizabad','Lodhran','Muzaffargarh','Rajanpur',
    'Pakpattan','Narowal','Attock','Chakwal','Murree','Talagang','Fort Abbas',
    'Haroonabad','Hasilpur','Arifwala','Kallar Kahar','Mailsi','Kot Addu',
    'Kabirwala','Samundri','Phalia','Kharian','Wazirabad','Shorkot','Jampur',
    'Khanpur','Shakargarh','Daska','Kamoke',
  ],
  'Sindh': [
    'Karachi','Hyderabad','Sukkur','Larkana','Mirpur Khas','Khairpur','Nawabshah',
    'Badin','Thatta','Jamshoro','Sanghar','Ghotki','Jacobabad','Shikarpur','Dadu',
    'Umerkot','Tando Adam','Tando Allahyar','Sehwan Sharif','Shahdadkot','Mithi',
    'Kandhkot','Kotri','Mirwah','Matli','Khipro','Tharparkar',
  ],
  'Khyber Pakhtunkhwa': [
    'Peshawar','Mardan','Mingora','Abbottabad','Kohat','Dera Ismail Khan','Bannu',
    'Chitral','Mansehra','Haripur','Swabi','Nowshera','Charsadda','Batkhela',
    'Shangla','Hangu','Timergara','Dir Upper','Karak','Lakki Marwat','Tank',
    'Parachinar','Jamrud','Kohistan',
  ],
  'Balochistan': [
    'Quetta','Gwadar','Turbat','Khuzdar','Chaman','Sibi','Zhob','Hub',
    'Killa Saifullah','Dera Murad Jamali','Awaran','Panjgur','Kharan','Washuk',
    'Loralai','Mastung','Ziarat','Pasni','Ormara','Jaffarabad',
  ],
  'Islamabad': ['Islamabad'],
  'Gilgit Baltistan': [
    'Gilgit','Skardu','Hunza','Chilas','Khaplu','Shigar','Astore','Nagar',
  ],
  'Azad Kashmir': [
    'Muzaffarabad','Mirpur','Rawalakot','Kotli','Bagh','Neelum Valley','Haveli',
  ],
  'Other': ['Other'],
};

// ── Caste list (grouped by origin) ───────────────────────────────────────────
/// Flat list for simple dropdowns / filter chips
const kCastes = [
  // Punjab
  'Jatt','Rajput','Arain','Gujjar','Sheikh','Syed','Mughal','Malik','Awan',
  'Bhatti','Khokhar','Dogar','Tiwana','Kamboh','Ansari','Qureshi',
  // Sindh
  'Sindhi Syed','Soomro','Junejo','Memon','Lohana','Khuhro','Chandio','Brohi',
  'Abbasi','Jatoi','Palijo',
  // Balochistan
  'Bugti','Marri','Mengal','Rind','Raisani',
  // KPK / Pashtun
  'Afridi','Yousafzai','Khattak','Shinwari','Bangash','Mohmand','Wazir','Mehsud','Tareen',
  // Kashmir & Northern
  'Butt','Dar','Lone','Mir','Chaudhry','Raja',
  // Urdu-speaking / Muhajir
  'Siddiqui','Farooqui','Usmani','Rizvi','Zaidi','Memon',
  'Other',
];

/// Grouped map for searchable dropdowns (origin → caste list)
const kCastesGrouped = <String, List<String>>{
  'Other': ['Other'],
  'Punjab': [
    'Jatt','Rajput','Arain','Gujjar','Sheikh','Syed','Mughal','Malik','Awan',
    'Bhatti','Khokhar','Dogar','Tiwana','Kamboh','Ansari','Qureshi',
  ],
  'Sindh': [
    'Sindhi Syed','Soomro','Junejo','Memon','Lohana','Khuhro','Chandio','Brohi',
    'Abbasi','Jatoi','Palijo',
  ],
  'Balochistan': ['Bugti','Marri','Mengal','Rind','Raisani'],
  'KPK / Pashtun': [
    'Afridi','Yousafzai','Khattak','Shinwari','Bangash','Mohmand','Wazir','Mehsud','Tareen',
  ],
  'Kashmir & Northern': ['Butt','Dar','Lone','Mir','Chaudhry','Raja'],
  'Urdu-speaking / Muhajir': ['Siddiqui','Farooqui','Usmani','Rizvi','Zaidi','Memon'],
};

// ── Sect list ─────────────────────────────────────────────────────────────────
const kSects = ['Sunni', 'Shia', 'Barelvi', 'Deobandi', 'Ahl-e-Hadith', 'Other'];
const kLanguages = ['Urdu', 'Punjabi', 'Pashto', 'Sindhi', 'Saraiki', 'Balochi', 'English'];

// ── Education list ────────────────────────────────────────────────────────────
const kEducations = [
  'Matric', 'FSc/FA', 'Diploma', 'Bachelor\'s', 'Master\'s',
  'MPhil', 'PhD', 'Other',
];

// ── Professions (full list — shared by FilterSheet & SubmitProposalScreen) ────
const kAllProfessions = [
  'Accountant','Actor','Administrative Officer','Advocate','Aeronautical Engineer',
  'Agricultural Engineer','Agriculture Officer','Air Hostess','Airline Pilot',
  'Architect','Army Officer','Artist','Auto Electrician','Automobile Engineer',
  'Baker','Bank Manager','Barber','Beautician','Biochemist','Biomedical Engineer',
  'Blogger','Brick Mason','Builder','Business Analyst','Business Owner',
  'Call Center Agent','Cameraman','Carpenter','Cashier','Chartered Accountant',
  'Chef','Chemical Engineer','Chemist','Civil Engineer','Clerk','Cloud Engineer',
  'Coach','Computer Engineer','Construction Manager','Consultant','Content Creator',
  'Copywriter','Courier Rider','CSS Officer','Cyber Security Expert',
  'Data Analyst','Data Scientist','Decorator','Delivery Rider','Dental Assistant',
  'Dentist','Dermatologist','Designer','Developer','Digital Marketer','Dispatcher',
  'Doctor','Driver','Drone Operator',
  'Economist','Editor','Electrician','Electrical Engineer','Electronics Engineer',
  'Embroidery Worker','ENT Specialist','Event Manager',
  'Fashion Designer','Farmer','Fashion Model','Field Officer','Financial Advisor',
  'Firefighter','Fisherman','Flight Engineer','Florist','Food Panda Rider',
  'Food Technologist','Freelance Writer','Freelancer','Frontend Developer',
  'Technician','General Manager','General Physician','Genetic Engineer',
  'Graphic Designer','Government Officer',
  'Hardware Engineer','Headmaster','Home Tutor','Hotel Manager','HR Manager',
  'Human Resource Officer',
  'Imam','Import Export Agent','Industrial Engineer','Influencer',
  'Information Security Analyst','Insurance Agent','Interior Designer',
  'Interpreter','Investment Banker','IT Administrator','IT Support Specialist',
  'Janitor','Java Developer','JazzCash Agent','Journalist','Judge',
  'Kitchen Helper','Kitchen Supervisor',
  'Lab Technician','Laboratory Scientist','Lawyer','Lecturer','Librarian',
  'Livestock Farmer','Logistic Manager',
  'Machine Operator','Makeup Artist','Marketing Manager','Mason',
  'Mechanical Engineer','Media Buyer','Medical Representative','Microbiologist',
  'Mobile Repair Technician','Model','Multimedia Specialist',
  'Naib Qasid','Network Administrator','Network Engineer','Nurse','Nutritionist',
  'Office Assistant','Operation Manager','Optician','Orthopedic Surgeon',
  'Painter','Pathologist','Pediatrician','Pharmacist','Photographer',
  'Physiotherapist','Pilot','Plumber','Police Officer','Politician','Principal',
  'Product Manager','Professor','Programmer','Project Manager','Property Dealer',
  'Psychiatrist','Psychologist','Public Relations Officer',
  'QA Engineer','Qari','Quantity Surveyor',
  'Radiologist','Railway Officer','Real Estate Agent','Receptionist',
  'Research Assistant','Research Scientist','Rider','Robotics Engineer',
  'Safety Officer','Sales Executive','School Teacher','Scientist','Security Guard',
  'SEO Expert','Shopkeeper','Social Media Manager','Social Worker',
  'Software Engineer','Solar Technician','Sound Engineer','Sports Coach',
  'Stenographer','Surgeon','Surveyor',
  'Tailor','Tax Consultant','Teacher','Telecom Engineer','Television Host',
  'Textile Designer','Textile Engineer','Tour Guide','Trader',
  'Traffic Police Officer','Trainer','Translator','Truck Driver',
  'UI Designer','UI/UX Designer','Ultrasound Technician','University Professor',
  'Veterinarian','Video Editor','Virtual Assistant',
  'Waiter','Warehouse Manager','Web Designer','Web Developer','Welder','Writer',
  'X-Ray Technician','YouTuber','Zoologist','Businessman','Housewife','Gardener','Butcher','Cobbler','Other',
];

// ── Profession groups (for filter — matches website categories) ───────────────
const kProfessionGroups = <String, List<String>>{
  'Healthcare': ['Doctor','General Physician','Dentist','Dermatologist','Pediatrician','Orthopedic Surgeon','Surgeon','ENT Specialist','Psychiatrist','Psychologist','Radiologist','Pathologist','Nurse','Nutritionist','Physiotherapist','Dental Assistant','Lab Technician','Pharmacist','Ultrasound Technician','Medical Representative','Optician','Microbiologist','Biochemist','Biomedical Engineer','Genetic Engineer'],
  'Engineering': ['Software Engineer','Civil Engineer','Mechanical Engineer','Electrical Engineer','Electronics Engineer','Chemical Engineer','Aeronautical Engineer','Agricultural Engineer','Automobile Engineer','Computer Engineer','Telecom Engineer','Textile Engineer','Industrial Engineer','Flight Engineer','Robotics Engineer','Hardware Engineer','Network Engineer','Cloud Engineer','Food Technologist','Quantity Surveyor'],
  'IT & Tech': ['Developer','Frontend Developer','Java Developer','Web Developer','Web Designer','UI Designer','UI/UX Designer','Graphic Designer','Programmer','Data Analyst','Data Scientist','Cyber Security Expert','Information Security Analyst','IT Administrator','IT Support Specialist','Network Administrator','SEO Expert','Digital Marketer','Social Media Manager','Blogger','Content Creator','Copywriter','Freelancer','YouTuber','QA Engineer','Drone Operator'],
  'Education': ['Teacher','School Teacher','Lecturer','Professor','University Professor','Principal','Headmaster','Home Tutor','Coach','Trainer','Qari','Research Scientist','Research Assistant'],
  'Finance & Law': ['Accountant','Chartered Accountant','Financial Advisor','Investment Banker','Tax Consultant','Insurance Agent','Economist','Business Analyst','Lawyer','Advocate','Judge','CSS Officer'],
  'Business & Management': ['Business Owner','General Manager','Operation Manager','Product Manager','Project Manager','HR Manager','Human Resource Officer','Marketing Manager','Sales Executive','Bank Manager','Hotel Manager','Construction Manager','Logistic Manager','Warehouse Manager','Import Export Agent','Property Dealer','Real Estate Agent','Trader','Consultant'],
  'Government & Forces': ['Army Officer','Police Officer','Traffic Police Officer','Government Officer','Administrative Officer','Agriculture Officer','Field Officer','Railway Officer','Naib Qasid','Security Guard','Firefighter'],
  'Arts & Media': ['Photographer','Videographer','Video Editor','Cameraman','Actor','Fashion Model','Model','Television Host','Journalist','Editor','Multimedia Specialist','Animator','Sound Engineer','Music Teacher','Influencer'],
  'Skilled Trades': ['Electrician','Plumber','Carpenter','Mason','Brick Mason','Welder','Painter','Auto Electrician','Mobile Repair Technician','Solar Technician','Technician','Machine Operator','Tailor','Embroidery Worker','Baker','Chef','Barber','Beautician'],
  'Services & Other': ['Driver','Truck Driver','Rider','Delivery Rider','Waiter','Receptionist','Cashier','Shopkeeper','Call Center Agent','Social Worker','Veterinarian','Farmer','Livestock Farmer','Interior Designer','Event Manager','Sports Coach','Athlete','Virtual Assistant','Scientist','Fashion Designer','Makeup Artist','Businessman','Housewife','Other'],
};

// ── Monthly income list ───────────────────────────────────────────────────────
const kMonthlyIncomes = [
  'Under 30K', '30K – 60K', '60K – 100K',
  '100K – 200K', '200K – 500K', '500K+',
];

// ── App Theme ─────────────────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: kSurface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPurple,
      brightness: Brightness.light,
    ),
    
    appBarTheme: const AppBarTheme(
      backgroundColor: kCardBg,
      foregroundColor: kInk,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: kInk,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle( color: kInk),
      bodyLarge: TextStyle( color: kInk),
      bodyMedium: TextStyle( color: kInk),
    ),
  );
}

const kProfessionsGrouped = <String, List<String>>{
  'Other': ['Other'],
  'Healthcare': [
    'Doctor', 'General Physician', 'Dentist', 'Dermatologist', 'Pediatrician',
    'Orthopedic Surgeon', 'Surgeon', 'ENT Specialist', 'Psychiatrist', 'Psychologist',
    'Radiologist', 'Pathologist', 'Nurse', 'Nutritionist', 'Physiotherapist',
    'Dental Assistant', 'Lab Technician', 'Pharmacist', 'Ultrasound Technician',
    'Medical Representative', 'Optician', 'Microbiologist', 'Biochemist',
    'Biomedical Engineer', 'Genetic Engineer',
  ],
  'Engineering': [
    'Software Engineer', 'Civil Engineer', 'Mechanical Engineer', 'Electrical Engineer',
    'Electronics Engineer', 'Chemical Engineer', 'Aeronautical Engineer', 'Agricultural Engineer',
    'Automobile Engineer', 'Computer Engineer', 'Telecom Engineer', 'Textile Engineer',
    'Industrial Engineer', 'Flight Engineer', 'Robotics Engineer', 'Hardware Engineer',
    'Network Engineer', 'Cloud Engineer', 'Biomedical Engineer',
    'Food Technologist', 'Quantity Surveyor',
  ],
  'IT & Tech': [
    'Developer', 'Frontend Developer', 'Java Developer', 'Web Developer', 'Web Designer',
    'UI Designer', 'UI/UX Designer', 'Graphic Designer', 'Programmer',
    'Data Analyst', 'Data Scientist', 'Cyber Security Expert', 'Information Security Analyst',
    'IT Administrator', 'IT Support Specialist', 'Network Administrator',
    'SEO Expert', 'Digital Marketer', 'Social Media Manager', 'Blogger',
    'Content Creator', 'Copywriter', 'Freelancer', 'YouTuber',
    'QA Engineer', 'Cloud Engineer', 'Drone Operator',
  ],
  'Education': [
    'Teacher', 'School Teacher', 'Lecturer', 'Professor', 'University Professor',
    'Principal', 'Headmaster', 'Home Tutor', 'Coach', 'Trainer', 'Qari',
    'Research Scientist', 'Research Assistant',
  ],
  'Finance & Law': [
    'Accountant', 'Chartered Accountant', 'Financial Advisor', 'Investment Banker',
    'Tax Consultant', 'Insurance Agent', 'Economist', 'Business Analyst',
    'Lawyer', 'Advocate', 'Judge', 'CSS Officer',
  ],
  'Business & Management': [
    'Business Owner', 'General Manager', 'Operation Manager', 'Product Manager',
    'Project Manager', 'HR Manager', 'Human Resource Officer', 'Marketing Manager',
    'Sales Executive', 'Bank Manager', 'Hotel Manager', 'Construction Manager',
    'Logistic Manager', 'Warehouse Manager', 'Import Export Agent',
    'Property Dealer', 'Real Estate Agent', 'Trader', 'Consultant',
  ],
  'Government & Forces': [
    'Army Officer', 'Police Officer', 'Traffic Police Officer', 'Government Officer',
    'Administrative Officer', 'Agriculture Officer', 'Field Officer', 'Railway Officer',
    'Naib Qasid', 'Security Guard', 'Firefighter',
  ],
  'Arts & Media': [
    'Photographer', 'Videographer', 'Video Editor', 'Cameraman', 'Actor',
    'Fashion Model', 'Model', 'Television Host', 'Journalist', 'Editor',
    'Multimedia Specialist', 'Animator', 'Sound Engineer', 'Music Teacher',
    'Influencer',
  ],
  'Skilled Trades': [
    'Electrician', 'Plumber', 'Carpenter', 'Mason', 'Brick Mason', 'Welder',
    'Painter', 'Auto Electrician', 'Mobile Repair Technician', 'Solar Technician',
    'Technician', 'Lab Technician', 'Machine Operator', 'Tailor',
    'Embroidery Worker', 'Baker', 'Chef', 'Barber', 'Beautician',
  ],
  'Services & Other': [
    'Driver', 'Truck Driver', 'Rider', 'Delivery Rider', 'Courier Rider',
    'Food Panda Rider', 'Waiter', 'Receptionist', 'Cashier', 'Shopkeeper',
    'JazzCash Agent', 'Call Center Agent', 'Dispatcher', 'Tour Guide',
    'Social Worker', 'Veterinarian', 'Farmer', 'Livestock Farmer', 'Fisherman',
    'Florist', 'Decorator', 'Interior Designer', 'Event Manager',
    'Sports Coach', 'Athlete', 'Stenographer', 'Librarian', 'Interpreter',
    'Translator', 'Virtual Assistant', 'Janitor', 'Kitchen Helper',
    'Kitchen Supervisor', 'Safety Officer', 'Surveyor', 'Public Relations Officer',
    'Zoologist', 'Scientist', 'Freelance Writer', 'Writer',
    'Fashion Designer', 'Textile Designer', 'Makeup Artist',
    'Businessman', 'Housewife', 'Gardener', 'Butcher', 'Cobbler',
  ],
};
