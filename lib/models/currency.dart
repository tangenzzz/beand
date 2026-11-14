// The currency of bean prices (Settings → Beans → Currency). One currency
// for the whole app: the price of a bag is stored as a bare number, the
// unit next to it comes from here.

class Currency {
  const Currency(this.code, this.name, this.symbol);

  /// ISO 4217 code, e.g. EUR. This is what is stored.
  final String code;
  final String name;

  /// Shown next to the price, e.g. "€" or "CHF".
  final String symbol;

  /// "Euro (€)" or, where the symbol is the code, "Swiss franc (CHF)".
  String get label => '$name ($symbol)';
}

const defaultCurrencyCode = 'EUR';

/// The most important currencies, the most likely ones first. Where several
/// countries use "$" or "kr", the symbol says which one.
const currencies = <Currency>[
  Currency('EUR', 'Euro', '€'),
  Currency('USD', 'US dollar', r'$'),
  Currency('GBP', 'British pound', '£'),
  Currency('CHF', 'Swiss franc', 'CHF'),
  Currency('CAD', 'Canadian dollar', r'CA$'),
  Currency('AUD', 'Australian dollar', r'A$'),
  Currency('NZD', 'New Zealand dollar', r'NZ$'),
  Currency('JPY', 'Japanese yen', '¥'),
  Currency('CNY', 'Chinese yuan', 'CN¥'),
  Currency('KRW', 'South Korean won', '₩'),
  Currency('HKD', 'Hong Kong dollar', r'HK$'),
  Currency('SGD', 'Singapore dollar', r'S$'),
  Currency('TWD', 'New Taiwan dollar', r'NT$'),
  Currency('SEK', 'Swedish krona', 'SEK'),
  Currency('NOK', 'Norwegian krone', 'NOK'),
  Currency('DKK', 'Danish krone', 'DKK'),
  Currency('PLN', 'Polish złoty', 'zł'),
  Currency('CZK', 'Czech koruna', 'Kč'),
  Currency('HUF', 'Hungarian forint', 'Ft'),
  Currency('TRY', 'Turkish lira', '₺'),
  Currency('INR', 'Indian rupee', '₹'),
  Currency('AED', 'UAE dirham', 'AED'),
  Currency('BRL', 'Brazilian real', r'R$'),
  Currency('MXN', 'Mexican peso', r'MX$'),
  Currency('ZAR', 'South African rand', 'R'),
];

/// The currency of [code]; an unknown or missing code falls back to euro.
Currency currencyFor(String? code) {
  final c = code?.trim().toUpperCase();
  for (final currency in currencies) {
    if (currency.code == c) return currency;
  }
  return currencies.first;
}

/// Whether [given] (a code like "usd" or a symbol like "€", as a shop page
/// or the AI writes it) means [currency]. Null or empty counts as a match:
/// a price without a currency is taken as the app's own.
bool currencyMatches(String? given, Currency currency) {
  final g = given?.trim().toUpperCase();
  if (g == null || g.isEmpty) return true;
  return g == currency.code || g == currency.symbol.toUpperCase();
}
