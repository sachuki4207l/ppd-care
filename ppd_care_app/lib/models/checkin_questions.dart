class CheckinQuestion {
  const CheckinQuestion({
    required this.key,
    required this.question,
    required this.choices,
  });

  final String key;
  final String question;
  final List<String> choices;
}

const List<CheckinQuestion> checkinQuestions = [
  CheckinQuestion(
    key: 'angry',
    question: 'Since the birth, have you felt angry more than usual?',
    choices: ['Yes', 'No'],
  ),
  CheckinQuestion(
    key: 'relax',
    question: 'Can you relax or sleep when your baby sleeps?',
    choices: ['Yes', 'No'],
  ),
  CheckinQuestion(
    key: 'trust',
    question: 'Do you have someone you trust and can share your feelings with?',
    choices: ['Yes', 'No'],
  ),
  CheckinQuestion(
    key: 'husband_rel',
    question: 'How is your relationship with your husband?',
    choices: ['Poor', 'Bad', 'Neutral', 'Friendly', 'Good'],
  ),
  CheckinQuestion(
    key: 'inlaw_rel',
    question: 'How is your relationship with your in-laws?',
    choices: ['Poor', 'Bad', 'Neutral', 'Friendly', 'Good'],
  ),
  CheckinQuestion(
    key: 'support',
    question: 'How much support do you receive?',
    choices: ['Low', 'Medium', 'High'],
  ),
  CheckinQuestion(
    key: 'motherhood',
    question: 'How do you feel about being a mother?',
    choices: ['Sad', 'Neutral', 'Happy'],
  ),
];
