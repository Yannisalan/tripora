import 'package:flutter/widgets.dart';

import '../preferences/app_preferences.dart';

/// Lightweight, code-generation-free localization layer.
///
/// Keyed strings are resolved against the user's preferred language (from
/// [AppPreferences]), falling back to English when a key or language is
/// missing. Strings that carry dynamic numbers keep their placeholders in
/// the source string (the surrounding interpolation is unchanged).
class AppLocalizations {
  AppLocalizations._();

  static const String fallbackLanguage = 'en';

  static const Map<String, Map<String, String>> _strings = {
    'nav.home': {
      'en': 'Home',
      'es': 'Inicio',
      'fr': "Accueil",
      'de': 'Start',
      'it': 'Home',
      'pt': 'Início',
    },
    'nav.explore': {
      'en': 'Explore',
      'es': 'Explorar',
      'fr': 'Explorer',
      'de': 'Entdecken',
      'it': 'Esplora',
      'pt': 'Explorar',
    },
    'nav.flights': {
      'en': 'Flights',
      'es': 'Vuelos',
      'fr': 'Vols',
      'de': 'Flüge',
      'it': 'Voli',
      'pt': 'Voos',
    },
    'nav.trips': {
      'en': 'My Trips',
      'es': 'Mis Viajes',
      'fr': 'Mes Voyages',
      'de': 'Meine Reisen',
      'it': 'I Miei Viaggi',
      'pt': 'Minhas Viagens',
    },
    'nav.profile': {
      'en': 'Profile',
      'es': 'Perfil',
      'fr': 'Profil',
      'de': 'Profil',
      'it': 'Profilo',
      'pt': 'Perfil',
    },
    'profile.myAccount': {
      'en': 'My Account',
      'es': 'Mi Cuenta',
      'fr': 'Mon Compte',
      'de': 'Mein Konto',
      'it': 'Il Mio Account',
      'pt': 'Minha Conta',
    },
    'profile.accountEyebrow': {
      'en': 'ACCOUNT',
      'es': 'CUENTA',
      'fr': 'COMPTE',
      'de': 'KONTO',
      'it': 'ACCOUNT',
      'pt': 'CONTA',
    },
    'profile.travelSettingsEyebrow': {
      'en': 'TRAVEL SETTINGS',
      'es': 'AJUSTES DE VIAJE',
      'fr': 'PRÉFÉRENCES DE VOYAGE',
      'de': 'REISEEINSTELLUNGEN',
      'it': 'IMPOSTAZIONI DI VIAGGIO',
      'pt': 'PREFERÊNCIAS DE VIAGEM',
    },
    'profile.personalDetails': {
      'en': 'Personal details',
      'es': 'Datos personales',
      'fr': 'Informations personnelles',
      'de': 'Persönliche Daten',
      'it': 'Dati personali',
      'pt': 'Dados pessoais',
    },
    'profile.preferences': {
      'en': 'Preferences',
      'es': 'Preferencias',
      'fr': 'Préférences',
      'de': 'Einstellungen',
      'it': 'Preferenze',
      'pt': 'Preferências',
    },
    'profile.preferredLanguage': {
      'en': 'Preferred language',
      'es': 'Idioma preferido',
      'fr': 'Langue préférée',
      'de': 'Bevorzugte Sprache',
      'it': 'Lingua preferita',
      'pt': 'Idioma preferido',
    },
    'profile.preferredCurrency': {
      'en': 'Preferred currency',
      'es': 'Moneda preferida',
      'fr': 'Devise préférée',
      'de': 'Bevorzugte Währung',
      'it': 'Valuta preferita',
      'pt': 'Moeda preferida',
    },
    'profile.fullName': {
      'en': 'Full name',
      'es': 'Nombre completo',
      'fr': 'Nom complet',
      'de': 'Vollständiger Name',
      'it': 'Nome completo',
      'pt': 'Nome completo',
    },
    'profile.emailAddress': {
      'en': 'Email address',
      'es': 'Correo electrónico',
      'fr': 'Adresse e-mail',
      'de': 'E-Mail-Adresse',
      'it': 'Indirizzo email',
      'pt': 'Endereço de e-mail',
    },
    'profile.saveChanges': {
      'en': 'Save Changes',
      'es': 'Guardar cambios',
      'fr': 'Enregistrer',
      'de': 'Änderungen speichern',
      'it': 'Salva modifiche',
      'pt': 'Salvar alterações',
    },
    'profile.saving': {
      'en': 'Saving...',
      'es': 'Guardando...',
      'fr': 'Enregistrement...',
      'de': 'Speichern...',
      'it': 'Salvataggio...',
      'pt': 'Salvando...',
    },
    'profile.updatedSuccess': {
      'en': 'Your account was updated successfully.',
      'es': 'Tu cuenta se actualizó correctamente.',
      'fr': 'Votre compte a bien été mis à jour.',
      'de': 'Dein Konto wurde erfolgreich aktualisiert.',
      'it': 'Il tuo account è stato aggiornato correttamente.',
      'pt': 'Sua conta foi atualizada com sucesso.',
    },
    'profile.prefSynced': {
      'en': 'Preferences synced to your account.',
      'es': 'Preferencias sincronizadas con tu cuenta.',
      'fr': 'Préférences synchronisées avec votre compte.',
      'de': 'Einstellungen mit deinem Konto synchronisiert.',
      'it': 'Preferenze sincronizzate con il tuo account.',
      'pt': 'Preferências sincronizadas com sua conta.',
    },
    'details.budget': {
      'en': 'BUDGET',
      'es': 'PRESUPUESTO',
      'fr': 'BUDGET',
      'de': 'BUDGET',
      'it': 'BUDGET',
      'pt': 'ORÇAMENTO',
    },
    'details.planComplete': {
      'en': 'PLAN COMPLETE',
      'es': 'PLAN COMPLETO',
      'fr': 'PLAN TERMINÉ',
      'de': 'PLAN VOLLSTÄNDIG',
      'it': 'PIANO COMPLETO',
      'pt': 'PLANO COMPLETO',
    },
    'details.duration': {
      'en': 'DURATION',
      'es': 'DURACIÓN',
      'fr': 'DURÉE',
      'de': 'DAUER',
      'it': 'DURATA',
      'pt': 'DURAÇÃO',
    },
    'details.estimatedCost': {
      'en': 'ESTIMATED COST',
      'es': 'COSTO ESTIMADO',
      'fr': 'COÛT ESTIMÉ',
      'de': 'GESCHÄTZTE KOSTEN',
      'it': 'COSTO STIMATO',
      'pt': 'CUSTO ESTIMADO',
    },
    'details.projectedTripSpend': {
      'en': 'Projected trip spend',
      'es': 'Gasto previsto del viaje',
      'fr': 'Dépenses de voyage prévues',
      'de': 'Voraussichtliche Reisekosten',
      'it': 'Spesa prevista del viaggio',
      'pt': 'Gastos previstos da viagem',
    },
    'details.commandDeck': {
      'en': 'TRIP COMMAND DECK',
      'es': 'CENTRO DE MANDO',
      'fr': 'TABLEAU DE BORD',
      'de': 'REISE-KONSOLLE',
      'it': 'PANNELLO DI COMANDO',
      'pt': 'PAINEL DE COMANDO',
    },
    'details.activities': {
      'en': 'Activities',
      'es': 'Actividades',
      'fr': 'Activités',
      'de': 'Aktivitäten',
      'it': 'Attività',
      'pt': 'Atividades',
    },
    'details.expenses': {
      'en': 'Expenses',
      'es': 'Gastos',
      'fr': 'Dépenses',
      'de': 'Ausgaben',
      'it': 'Spese',
      'pt': 'Despesas',
    },
    'details.activitiesPlanned': {
      'en': '{n} planned',
      'es': '{n} planificadas',
      'fr': '{n} prévues',
      'de': '{n} geplant',
      'it': '{n} pianificate',
      'pt': '{n} planejadas',
    },
    'details.trackSpending': {
      'en': 'Track your spending',
      'es': 'Controla tus gastos',
      'fr': 'Suivez vos dépenses',
      'de': 'Ausgaben verfolgen',
      'it': 'Traccia le tue spese',
      'pt': 'Acompanhe seus gastos',
    },
    'details.weather': {
      'en': 'Weather',
      'es': 'Clima',
      'fr': 'Météo',
      'de': 'Wetter',
      'it': 'Meteo',
      'pt': 'Clima',
    },
    'details.weatherForecast': {
      'en': 'View forecast',
      'es': 'Ver pronóstico',
      'fr': 'Voir les prévisions',
      'de': 'Vorhersage',
      'it': 'Vedi previsioni',
      'pt': 'Ver previsão',
    },
    'weather.title': {
      'en': 'Weather',
      'es': 'Clima',
      'fr': 'Météo',
      'de': 'Wetter',
      'it': 'Meteo',
      'pt': 'Clima',
    },
    'weather.error': {
      'en': 'Something went wrong',
      'es': 'Algo salió mal',
      'fr': "Quelque chose s'est mal passé",
      'de': 'Etwas ist schiefgelaufen',
      'it': 'Qualcosa è andato storto',
      'pt': 'Algo deu errado',
    },
    'weather.unavailable': {
      'en': 'Weather data is not available right now.',
      'es': 'Los datos del clima no están disponibles.',
      'fr': 'Les données météo ne sont pas disponibles.',
      'de': 'Wetterdaten sind derzeit nicht verfügbar.',
      'it': 'I dati meteo non sono disponibili.',
      'pt': 'Dados do clima não estão disponíveis.',
    },
    'weather.noForecast': {
      'en': 'No forecast for this range',
      'es': 'Sin pronóstico para este rango',
      'fr': 'Aucune prévision pour cette période',
      'de': 'Keine Vorhersage für diesen Zeitraum',
      'it': 'Nessuna previsione per questo periodo',
      'pt': 'Sem previsão para este período',
    },
    'weather.retry': {
      'en': 'Try again',
      'es': 'Intentar de nuevo',
      'fr': 'Réessayer',
      'de': 'Erneut versuchen',
      'it': 'Riprova',
      'pt': 'Tentar novamente',
    },
    'it.estimatedCost': {
      'en': 'ESTIMATED COST',
      'es': 'COSTO ESTIMADO',
      'fr': 'COÛT ESTIMÉ',
      'de': 'GESCHÄTZTE KOSTEN',
      'it': 'COSTO STIMATO',
      'pt': 'CUSTO ESTIMADO',
    },
    'it.tripBudgetOverview': {
      'en': 'Trip budget overview',
      'es': 'Resumen del presupuesto',
      'fr': 'Aperçu du budget du voyage',
      'de': 'Reisebudget im Überblick',
      'it': "Panoramica del budget di viaggio",
      'pt': 'Resumo do orçamento',
    },
    'it.approxCost': {
      'en': 'Approximate cost for your trip. Actual prices may vary.',
      'es': 'Costo aproximado de tu viaje. Los precios reales pueden variar.',
      'fr': 'Coût approximatif de votre voyage. Les prix réels peuvent varier.',
      'de': 'Ungefähre Kosten für deine Reise. Die tatsächlichen Preise können abweichen.',
      'it': 'Costo approssimativo del viaggio. I prezzi reali possono variare.',
      'pt': 'Custo aproximado da sua viagem. Os preços reais podem variar.',
    },
    'it.accommodation': {
      'en': 'Accommodation',
      'es': 'Alojamiento',
      'fr': 'Hébergement',
      'de': 'Unterkunft',
      'it': 'Alloggio',
      'pt': 'Acomodação',
    },
    'it.food': {
      'en': 'Food',
      'es': 'Comida',
      'fr': 'Repas',
      'de': 'Verpflegung',
      'it': 'Cibo',
      'pt': 'Alimentação',
    },
    'it.transportation': {
      'en': 'Transportation',
      'es': 'Transporte',
      'fr': 'Transport',
      'de': 'Transport',
      'it': 'Trasporti',
      'pt': 'Transporte',
    },
    'it.activities': {
      'en': 'Activities',
      'es': 'Actividades',
      'fr': 'Activités',
      'de': 'Aktivitäten',
      'it': 'Attività',
      'pt': 'Atividades',
    },
    'it.days': {
      'en': 'days',
      'es': 'días',
      'fr': 'jours',
      'de': 'Tage',
      'it': 'giorni',
      'pt': 'dias',
    },
    'it.travelerOne': {
      'en': 'traveler',
      'es': 'viajero',
      'fr': 'voyageur',
      'de': 'Reisender',
      'it': 'viaggiatore',
      'pt': 'viajante',
    },
    'it.travelerPlural': {
      'en': 'travelers',
      'es': 'viajeros',
      'fr': 'voyageurs',
      'de': 'Reisende',
      'it': 'viaggiatori',
      'pt': 'viajantes',
    },
  };

  /// Resolve [key] in [language]; falls back to English, then to the key
  /// itself so a missing entry never throws or renders blank.
  static String resolve(String key, String language) {
    final table = _strings[key];

    if (table == null) {
      return key;
    }

    return table[language] ?? table[fallbackLanguage] ?? key;
  }

  /// Translate [key] for the current [AppPreferences] language.
  static String current(String key) {
    return resolve(key, AppPreferences.instance.language);
  }
}

extension AppLocalizationsX on BuildContext {
  /// Shorthand for `AppLocalizations.current(key)`.
  String tr(String key) => AppLocalizations.current(key);
}