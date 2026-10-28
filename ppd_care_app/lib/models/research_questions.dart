enum ResearchSection { aboutYou, family, pregnancy, baby, feelings }

class ResearchOption {
  const ResearchOption(this.label, this.featureValues);

  final String label;
  final Map<String, int> featureValues;
}

class ResearchQuestion {
  const ResearchQuestion({
    required this.key,
    required this.section,
    required this.prompt,
    required this.options,
  });

  final String key;
  final ResearchSection section;
  final String prompt;
  final List<ResearchOption> options;
}

class EpdsQuestion {
  const EpdsQuestion(this.prompt, this.options);

  final String prompt;
  final List<String> options;
}

const String researchConsentHeading = 'Taking part in research';
const String researchIdPreferenceKey = 'research_id';
const String researchConsentDraft =
    'This voluntary questionnaire asks about your experiences during pregnancy '
    'and after birth. Your answers are sent to the research service separately '
    'from your personal check-ins. You may withdraw later from this device. '
    'Please take your time and choose only what you are comfortable sharing.';
const String researchConsentReviewNotice =
    'Draft information — TODO: ethics review before research use.';
const String abusePrompt =
    'Has anyone close to you hurt you physically, emotionally or sexually '
    'during or after your pregnancy?';
const String abusePrivacyNote =
    'You can skip this by choosing No; it stays private. '
    'TODO: supervisor review this wording.';

const List<String> researchSectionTitles = [
  'About you',
  'Family',
  'Pregnancy',
  'Baby',
  'Feelings',
];

const List<ResearchQuestion> researchQuestions = [
  ResearchQuestion(
    key: 'education',
    section: ResearchSection.aboutYou,
    prompt: 'What is the highest level of education you completed?',
    options: [
      ResearchOption('Primary school', {'Education Level': 0}),
      ResearchOption('High school', {'Education Level': 1}),
      ResearchOption('College', {'Education Level': 2}),
      ResearchOption('University', {'Education Level': 3}),
    ],
  ),
  ResearchQuestion(
    key: 'current_income',
    section: ResearchSection.aboutYou,
    prompt: 'What is your current monthly income?',
    options: [
      ResearchOption('No income', {'Current monthly income': 0}),
      ResearchOption('<5000', {'Current monthly income': 1}),
      ResearchOption('5000-10000', {'Current monthly income': 2}),
      ResearchOption('10000-20000', {'Current monthly income': 3}),
      ResearchOption('20000-30000', {'Current monthly income': 4}),
      ResearchOption('>30000', {'Current monthly income': 5}),
    ],
  ),
  ResearchQuestion(
    key: 'husband_income',
    section: ResearchSection.aboutYou,
    prompt: 'What is your husband’s monthly income?',
    options: [
      ResearchOption('<5000', {'Husband’s monthly income': 0}),
      ResearchOption('5000-10000', {'Husband’s monthly income': 1}),
      ResearchOption('10000-20000', {'Husband’s monthly income': 2}),
      ResearchOption('20000-30000', {'Husband’s monthly income': 3}),
      ResearchOption('>30000', {'Husband’s monthly income': 4}),
    ],
  ),
  ResearchQuestion(
    key: 'occupation',
    section: ResearchSection.aboutYou,
    prompt: 'What was your occupation before your latest pregnancy?',
    options: [
      ResearchOption('Housewife', {
        'Occupation before latest pregnancy_Housewife': 1,
        'Occupation before latest pregnancy_Student': 0,
      }),
      ResearchOption('Student', {
        'Occupation before latest pregnancy_Housewife': 0,
        'Occupation before latest pregnancy_Student': 1,
      }),
      ResearchOption('Other', {
        'Occupation before latest pregnancy_Housewife': 0,
        'Occupation before latest pregnancy_Student': 0,
      }),
    ],
  ),
  ResearchQuestion(
    key: 'children',
    section: ResearchSection.family,
    prompt: 'How many children do you have?',
    options: [
      ResearchOption('One', {'Total children': 0}),
      ResearchOption('Two', {'Total children': 1}),
      ResearchOption('More than two', {'Total children': 2}),
    ],
  ),
  ResearchQuestion(
    key: 'family_type',
    section: ResearchSection.family,
    prompt: 'Which best describes your family?',
    options: [
      ResearchOption('Nuclear', {'Family type': 0}),
      ResearchOption('Joint', {'Family type': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'inlaw_relationship',
    section: ResearchSection.family,
    prompt: 'How would you describe your relationship with your in-laws?',
    options: [
      ResearchOption('Poor', {'Relationship with the in-laws': 0}),
      ResearchOption('Bad', {'Relationship with the in-laws': 1}),
      ResearchOption('Neutral', {'Relationship with the in-laws': 2}),
      ResearchOption('Friendly', {'Relationship with the in-laws': 3}),
      ResearchOption('Good', {'Relationship with the in-laws': 4}),
    ],
  ),
  ResearchQuestion(
    key: 'husband_relationship',
    section: ResearchSection.family,
    prompt: 'How would you describe your relationship with your husband?',
    options: [
      ResearchOption('Poor', {'Relationship with husband': 0}),
      ResearchOption('Bad', {'Relationship with husband': 1}),
      ResearchOption('Neutral', {'Relationship with husband': 2}),
      ResearchOption('Friendly', {'Relationship with husband': 3}),
      ResearchOption('Good', {'Relationship with husband': 4}),
    ],
  ),
  ResearchQuestion(
    key: 'major_changes',
    section: ResearchSection.pregnancy,
    prompt: 'Did you experience major changes or losses during pregnancy?',
    options: [
      ResearchOption('No', {'Major changes or losses during pregnancy': 0}),
      ResearchOption('Yes', {'Major changes or losses during pregnancy': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'trust',
    section: ResearchSection.pregnancy,
    prompt: 'Do you have someone you trust and can share your feelings with?',
    options: [
      ResearchOption('No', {'Trust and share feelings': 0}),
      ResearchOption('Yes', {'Trust and share feelings': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'fear',
    section: ResearchSection.pregnancy,
    prompt: 'Did you feel afraid during pregnancy?',
    options: [
      ResearchOption('No', {'Fear of pregnancy': 0}),
      ResearchOption('Yes', {'Fear of pregnancy': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'disease',
    section: ResearchSection.pregnancy,
    prompt: 'Did you have a disease during pregnancy?',
    options: [
      ResearchOption('None', {'Diseases during pregnancy': 0}),
      ResearchOption('Non-chronic disease', {'Diseases during pregnancy': 1}),
      ResearchOption('Chronic disease', {'Diseases during pregnancy': 2}),
    ],
  ),
  ResearchQuestion(
    key: 'depression_before',
    section: ResearchSection.pregnancy,
    prompt:
        'Before pregnancy, did you feel down, depressed or hopeless, or have '
        'little interest in things?',
    options: [
      ResearchOption('No', {'Depression before pregnancy (PHQ2)': 0}),
      ResearchOption('Yes', {'Depression before pregnancy (PHQ2)': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'newborn_relationship',
    section: ResearchSection.baby,
    prompt: 'How would you describe your relationship with your newborn?',
    options: [
      ResearchOption('Bad', {'Relationship with the newborn': 0}),
      ResearchOption('Neutral', {'Relationship with the newborn': 1}),
      ResearchOption('Good', {'Relationship with the newborn': 2}),
      ResearchOption('Very good', {'Relationship with the newborn': 3}),
    ],
  ),
  ResearchQuestion(
    key: 'father_newborn_relationship',
    section: ResearchSection.baby,
    prompt:
        'How would you describe the relationship between the father and your '
        'newborn?',
    options: [
      ResearchOption('Bad', {'Relationship between father and newborn': 0}),
      ResearchOption('Neutral', {'Relationship between father and newborn': 1}),
      ResearchOption('Good', {'Relationship between father and newborn': 2}),
      ResearchOption('Very good', {
        'Relationship between father and newborn': 3,
      }),
    ],
  ),
  ResearchQuestion(
    key: 'newborn_gender',
    section: ResearchSection.baby,
    prompt: 'What is your newborn’s gender?',
    options: [
      ResearchOption('Girl', {'Gender of newborn': 0}),
      ResearchOption('Boy', {'Gender of newborn': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'birth',
    section: ResearchSection.baby,
    prompt: 'Were there complications during birth?',
    options: [
      ResearchOption('No', {'Birth compliancy': 0}),
      ResearchOption('Yes', {'Birth compliancy': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'breastfeed',
    section: ResearchSection.baby,
    prompt: 'Are you breastfeeding your baby?',
    options: [
      ResearchOption('No', {'Breastfeed': 0}),
      ResearchOption('Yes', {'Breastfeed': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'worry',
    section: ResearchSection.baby,
    prompt: 'Are you worried about your newborn?',
    options: [
      ResearchOption('No', {'Worry about newborn': 0}),
      ResearchOption('Yes', {'Worry about newborn': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'motherhood',
    section: ResearchSection.feelings,
    prompt: 'How do you feel about being a mother?',
    options: [
      ResearchOption('Sad', {'Feeling about motherhood': 0}),
      ResearchOption('Neutral', {'Feeling about motherhood': 1}),
      ResearchOption('Happy', {'Feeling about motherhood': 2}),
    ],
  ),
  ResearchQuestion(
    key: 'support_received',
    section: ResearchSection.feelings,
    prompt: 'How much support do you receive?',
    options: [
      ResearchOption('Low', {'Recieved Support': 0}),
      ResearchOption('Medium', {'Recieved Support': 1}),
      ResearchOption('High', {'Recieved Support': 2}),
    ],
  ),
  ResearchQuestion(
    key: 'relax',
    section: ResearchSection.feelings,
    prompt: 'Can you relax or sleep when your baby sleeps?',
    options: [
      ResearchOption('No', {'Relax/sleep when the newborn is asleep': 0}),
      ResearchOption('Yes', {'Relax/sleep when the newborn is asleep': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'anger',
    section: ResearchSection.feelings,
    prompt: 'Since the birth, have you felt angry more than usual?',
    options: [
      ResearchOption('No', {'Angry after latest child birth': 0}),
      ResearchOption('Yes', {'Angry after latest child birth': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'depression_during',
    section: ResearchSection.feelings,
    prompt:
        'During pregnancy, did you feel down, depressed or hopeless, or have '
        'little interest in things?',
    options: [
      ResearchOption('No', {'Depression during pregnancy (PHQ2)': 0}),
      ResearchOption('Yes', {'Depression during pregnancy (PHQ2)': 1}),
    ],
  ),
  ResearchQuestion(
    key: 'activities',
    section: ResearchSection.feelings,
    prompt: 'How do you usually feel about your regular activities?',
    options: [
      ResearchOption('Normal', {'Feeling for regular activities_Normal': 1}),
      ResearchOption('Tired', {'Feeling for regular activities_Normal': 0}),
      ResearchOption('Worried', {'Feeling for regular activities_Normal': 0}),
      ResearchOption('Afraid', {'Feeling for regular activities_Normal': 0}),
    ],
  ),
  ResearchQuestion(
    key: 'support_need',
    section: ResearchSection.feelings,
    prompt: 'How much support do you think you need?',
    options: [
      ResearchOption('Low', {'Need for Support_Unknown': 0}),
      ResearchOption('Medium', {'Need for Support_Unknown': 0}),
      ResearchOption('High', {'Need for Support_Unknown': 0}),
      ResearchOption('Not sure', {'Need for Support_Unknown': 1}),
    ],
  ),
];

const List<ResearchOption> abuseOptions = [
  // This mapping to the historical "Abuse" feature is unconfirmed.
  ResearchOption('No', {'abuse_reworded': 0}),
  ResearchOption('Yes', {'abuse_reworded': 1}),
];

const List<EpdsQuestion> epdsQuestions = [
  EpdsQuestion('I have been able to laugh and see the funny side of things', [
    'As much as I always could',
    'Not quite so much now',
    'Definitely not so much now',
    'Not at all',
  ]),
  EpdsQuestion('I have looked forward with enjoyment to things', [
    'As much as I ever did',
    'Rather less than I used to',
    'Definitely less than I used to',
    'Hardly at all',
  ]),
  EpdsQuestion('I have blamed myself unnecessarily when things went wrong', [
    'Yes, most of the time',
    'Yes, some of the time',
    'Not very often',
    'No, never',
  ]),
  EpdsQuestion('I have been anxious or worried for no good reason', [
    'No, not at all',
    'Hardly ever',
    'Yes, sometimes',
    'Yes, very often',
  ]),
  EpdsQuestion('I have felt scared or panicky for no good reason', [
    'Yes, quite a lot',
    'Yes, sometimes',
    'No, not much',
    'No, not at all',
  ]),
  EpdsQuestion('Things have been getting on top of me', [
    "Yes, most of the time I haven't been able to cope at all",
    "Yes, sometimes I haven't been coping as well as usual",
    'No, most of the time I have coped quite well',
    'No, I have been coping as well as ever',
  ]),
  EpdsQuestion('I have been so unhappy that I have had difficulty sleeping', [
    'Yes, most of the time',
    'Yes, sometimes',
    'Not very often',
    'No, not at all',
  ]),
  EpdsQuestion('I have felt sad or miserable', [
    'Yes, most of the time',
    'Yes, quite often',
    'Not very often',
    'No, not at all',
  ]),
  EpdsQuestion('I have been so unhappy that I have been crying', [
    'Yes, most of the time',
    'Yes, quite often',
    'Only occasionally',
    'No, never',
  ]),
  EpdsQuestion('The thought of harming myself has occurred to me', [
    'Yes, quite often',
    'Sometimes',
    'Hardly ever',
    'Never',
  ]),
];

const List<String> researchFeatureNames = [
  'Education Level',
  'Current monthly income',
  'Husband’s monthly income',
  'Total children',
  'Family type',
  'Relationship with the in-laws',
  'Relationship with husband',
  'Relationship with the newborn',
  'Relationship between father and newborn',
  'Feeling about motherhood',
  'Recieved Support',
  'Major changes or losses during pregnancy',
  'Trust and share feelings',
  'Fear of pregnancy',
  'Diseases during pregnancy',
  'Gender of newborn',
  'Birth compliancy',
  'Breastfeed',
  'Worry about newborn',
  'Relax/sleep when the newborn is asleep',
  'Angry after latest child birth',
  'Depression before pregnancy (PHQ2)',
  'Depression during pregnancy (PHQ2)',
  'Occupation before latest pregnancy_Housewife',
  'Occupation before latest pregnancy_Student',
  'Feeling for regular activities_Normal',
  'Need for Support_Unknown',
];

const Map<String, int> researchFeatureMaximums = {
  'Education Level': 3,
  'Current monthly income': 5,
  'Husband’s monthly income': 4,
  'Total children': 2,
  'Family type': 1,
  'Relationship with the in-laws': 4,
  'Relationship with husband': 4,
  'Relationship with the newborn': 3,
  'Relationship between father and newborn': 3,
  'Feeling about motherhood': 2,
  'Recieved Support': 2,
  'Major changes or losses during pregnancy': 1,
  'Trust and share feelings': 1,
  'Fear of pregnancy': 1,
  'Diseases during pregnancy': 2,
  'Gender of newborn': 1,
  'Birth compliancy': 1,
  'Breastfeed': 1,
  'Worry about newborn': 1,
  'Relax/sleep when the newborn is asleep': 1,
  'Angry after latest child birth': 1,
  'Depression before pregnancy (PHQ2)': 1,
  'Depression during pregnancy (PHQ2)': 1,
  'Occupation before latest pregnancy_Housewife': 1,
  'Occupation before latest pregnancy_Student': 1,
  'Feeling for regular activities_Normal': 1,
  'Need for Support_Unknown': 1,
};

Map<String, int> buildResearchFeatures({
  required Map<String, int> selectedQuestionOptions,
}) {
  final features = <String, int>{};
  for (final question in researchQuestions) {
    final selectedIndex = selectedQuestionOptions[question.key];
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= question.options.length) {
      continue;
    }
    features.addAll(question.options[selectedIndex].featureValues);
  }
  return {
    for (final name in researchFeatureNames)
      if (features.containsKey(name)) name: features[name]!,
  };
}
