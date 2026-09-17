import 'package:flutter/widgets.dart';

import '../preferences/app_preferences.dart';

/// Lightweight, code-generation-free localization layer.
///
/// Translations are resolved using the language selected in
/// [AppPreferences]. English is used as the fallback language.
///
/// Example:
///   context.tr('nav.home')
///
/// Dynamic translations:
///   context.tr(
///     'details.activitiesPlanned',
///     params: {'n': '8'},
///   );
class AppLocalizations {
  AppLocalizations._();

  static const String fallbackLanguage = 'en';

  static const Map<String, Map<String, String>> _strings = {
    // ============================================================
    // NAVIGATION
    // ============================================================

    'nav.home': {
      'en': 'Home',
      'es': 'Inicio',
      'fr': 'Accueil',
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
    'nav.planTrip': {
      'en': 'Plan a Trip',
      'es': 'Planear un Viaje',
      'fr': 'Planifier un Voyage',
      'de': 'Reise Planen',
      'it': 'Pianifica un Viaggio',
      'pt': 'Planejar uma Viagem',
    },

    // ============================================================
    // COMMON
    // ============================================================

    'common.save': {
      'en': 'Save',
      'es': 'Guardar',
      'fr': 'Enregistrer',
      'de': 'Speichern',
      'it': 'Salva',
      'pt': 'Salvar',
    },
    'common.cancel': {
      'en': 'Cancel',
      'es': 'Cancelar',
      'fr': 'Annuler',
      'de': 'Abbrechen',
      'it': 'Annulla',
      'pt': 'Cancelar',
    },
    'common.close': {
      'en': 'Close',
      'es': 'Cerrar',
      'fr': 'Fermer',
      'de': 'Schließen',
      'it': 'Chiudi',
      'pt': 'Fechar',
    },
    'common.delete': {
      'en': 'Delete',
      'es': 'Eliminar',
      'fr': 'Supprimer',
      'de': 'Löschen',
      'it': 'Elimina',
      'pt': 'Excluir',
    },
    'common.edit': {
      'en': 'Edit',
      'es': 'Editar',
      'fr': 'Modifier',
      'de': 'Bearbeiten',
      'it': 'Modifica',
      'pt': 'Editar',
    },
    'common.done': {
      'en': 'Done',
      'es': 'Done',
      'fr': 'Terminé',
      'de': 'Fertig',
      'it': 'Fatto',
      'pt': 'Concluído',
    },
    'common.continue': {
      'en': 'Continue',
      'es': 'Continuar',
      'fr': 'Continuer',
      'de': 'Weiter',
      'it': 'Continua',
      'pt': 'Continuar',
    },
    'common.back': {
      'en': 'Back',
      'es': 'Atrás',
      'fr': 'Retour',
      'de': 'Zurück',
      'it': 'Indietro',
      'pt': 'Voltar',
    },
    'common.next': {
      'en': 'Next',
      'es': 'Siguiente',
      'fr': 'Suivant',
      'de': 'Weiter',
      'it': 'Avanti',
      'pt': 'Próximo',
    },
    'common.retry': {
      'en': 'Retry',
      'es': 'Reintentar',
      'fr': 'Réessayer',
      'de': 'Erneut versuchen',
      'it': 'Riprova',
      'pt': 'Tentar novamente',
    },
    'common.loading': {
      'en': 'Loading...',
      'es': 'Cargando...',
      'fr': 'Chargement...',
      'de': 'Wird geladen...',
      'it': 'Caricamento...',
      'pt': 'Carregando...',
    },
    'common.error': {
      'en': 'Something went wrong',
      'es': 'Algo salió mal',
      'fr': "Quelque chose s'est mal passé",
      'de': 'Etwas ist schiefgelaufen',
      'it': 'Qualcosa è andato storto',
      'pt': 'Algo deu errado',
    },
    'common.success': {
      'en': 'Success',
      'es': 'Éxito',
      'fr': 'Succès',
      'de': 'Erfolg',
      'it': 'Successo',
      'pt': 'Sucesso',
    },
    'common.yes': {
      'en': 'Yes',
      'es': 'Sí',
      'fr': 'Oui',
      'de': 'Ja',
      'it': 'Sì',
      'pt': 'Sim',
    },
    'common.no': {
      'en': 'No',
      'es': 'No',
      'fr': 'Non',
      'de': 'Nein',
      'it': 'No',
      'pt': 'Não',
    },
    'common.confirm': {
      'en': 'Confirm',
      'es': 'Confirmar',
      'fr': 'Confirmer',
      'de': 'Bestätigen',
      'it': 'Conferma',
      'pt': 'Confirmar',
    },
    'common.search': {
      'en': 'Search',
      'es': 'Buscar',
      'fr': 'Rechercher',
      'de': 'Suchen',
      'it': 'Cerca',
      'pt': 'Pesquisar',
    },
    'common.seeAll': {
      'en': 'See all',
      'es': 'Ver todo',
      'fr': 'Voir tout',
      'de': 'Alle anzeigen',
      'it': 'Vedi tutto',
      'pt': 'Ver tudo',
    },

    // ============================================================
    // PROFILE
    // ============================================================

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

    // ============================================================
    // HOME
    // ============================================================

    'home.planTrip': {
      'en': 'Plan a Trip',
      'es': 'Planear un Viaje',
      'fr': 'Planifier un Voyage',
      'de': 'Reise planen',
      'it': 'Pianifica un viaggio',
      'pt': 'Planejar uma viagem',
    },
    'home.savedTrips': {
      'en': 'Saved trips',
      'es': 'Viajes guardados',
      'fr': 'Voyages enregistrés',
      'de': 'Gespeicherte Reisen',
      'it': 'Viaggi salvati',
      'pt': 'Viagens salvas',
    },
    'home.recentTrips': {
      'en': 'Recent trips',
      'es': 'Viajes recientes',
      'fr': 'Voyages récents',
      'de': 'Letzte Reisen',
      'it': 'Viaggi recenti',
      'pt': 'Viagens recentes',
    },
    'home.popularDestinations': {
      'en': 'Popular destinations',
      'es': 'Destinos populares',
      'fr': 'Destinations populaires',
      'de': 'Beliebte Reiseziele',
      'it': 'Destinazioni popolari',
      'pt': 'Destinos populares',
    },
    'home.exploreDestinations': {
      'en': 'Explore destinations',
      'es': 'Explorar destinos',
      'fr': 'Explorer les destinations',
      'de': 'Reiseziele entdecken',
      'it': 'Esplora le destinazioni',
      'pt': 'Explorar destinos',
    },
    'home.startPlanning': {
      'en': 'Start planning',
      'es': 'Comenzar a planificar',
      'fr': 'Commencer à planifier',
      'de': 'Planung starten',
      'it': 'Inizia a pianificare',
      'pt': 'Começar a planejar',
    },
    'home.noTrips': {
      'en': 'No trips yet',
      'es': 'Aún no hay viajes',
      'fr': 'Aucun voyage pour le moment',
      'de': 'Noch keine Reisen',
      'it': 'Nessun viaggio ancora',
      'pt': 'Nenhuma viagem ainda',
    },
    'home.viewAll': {
      'en': 'View all',
      'es': 'Ver todo',
      'fr': 'Voir tout',
      'de': 'Alle anzeigen',
      'it': 'Vedi tutto',
      'pt': 'Ver tudo',
    },

    // ============================================================
    // EXPLORE
    // ============================================================

    'explore.title': {
      'en': 'Explore',
      'es': 'Explorar',
      'fr': 'Explorer',
      'de': 'Entdecken',
      'it': 'Esplora',
      'pt': 'Explorar',
    },
    'explore.search': {
      'en': 'Search destinations',
      'es': 'Buscar destinos',
      'fr': 'Rechercher des destinations',
      'de': 'Reiseziele suchen',
      'it': 'Cerca destinazioni',
      'pt': 'Pesquisar destinos',
    },
    'explore.popular': {
      'en': 'Popular',
      'es': 'Populares',
      'fr': 'Populaires',
      'de': 'Beliebt',
      'it': 'Popolari',
      'pt': 'Populares',
    },
    'explore.recommended': {
      'en': 'Recommended',
      'es': 'Recomendados',
      'fr': 'Recommandés',
      'de': 'Empfohlen',
      'it': 'Consigliati',
      'pt': 'Recomendados',
    },
    'explore.destinations': {
      'en': 'Destinations',
      'es': 'Destinos',
      'fr': 'Destinations',
      'de': 'Reiseziele',
      'it': 'Destinazioni',
      'pt': 'Destinos',
    },
    'explore.viewDetails': {
      'en': 'View details',
      'es': 'Ver detalles',
      'fr': 'Voir les détails',
      'de': 'Details anzeigen',
      'it': 'Vedi dettagli',
      'pt': 'Ver detalhes',
    },

    // ============================================================
    // PLANNER
    // ============================================================

    'planner.title': {
      'en': 'Plan your trip',
      'es': 'Planifica tu viaje',
      'fr': 'Planifiez votre voyage',
      'de': 'Plane deine Reise',
      'it': 'Pianifica il tuo viaggio',
      'pt': 'Planeje sua viagem',
    },
    'planner.destination': {
      'en': 'Destination',
      'es': 'Destino',
      'fr': 'Destination',
      'de': 'Reiseziel',
      'it': 'Destinazione',
      'pt': 'Destino',
    },
    'planner.startDate': {
      'en': 'Start date',
      'es': 'Fecha de inicio',
      'fr': 'Date de début',
      'de': 'Startdatum',
      'it': 'Data di inizio',
      'pt': 'Data de início',
    },
    'planner.endDate': {
      'en': 'End date',
      'es': 'Fecha de finalización',
      'fr': 'Date de fin',
      'de': 'Enddatum',
      'it': 'Data di fine',
      'pt': 'Data de término',
    },
    'planner.travelers': {
      'en': 'Travelers',
      'es': 'Viajeros',
      'fr': 'Voyageurs',
      'de': 'Reisende',
      'it': 'Viaggiatori',
      'pt': 'Viajantes',
    },
    'planner.budget': {
      'en': 'Budget',
      'es': 'Presupuesto',
      'fr': 'Budget',
      'de': 'Budget',
      'it': 'Budget',
      'pt': 'Orçamento',
    },
    'planner.travelStyle': {
      'en': 'Travel style',
      'es': 'Estilo de viaje',
      'fr': 'Style de voyage',
      'de': 'Reisestil',
      'it': 'Stile di viaggio',
      'pt': 'Estilo de viagem',
    },
    'planner.interests': {
      'en': 'Interests',
      'es': 'Intereses',
      'fr': 'Centres d’intérêt',
      'de': 'Interessen',
      'it': 'Interessi',
      'pt': 'Interesses',
    },
    'planner.generate': {
      'en': 'Generate itinerary',
      'es': 'Generar itinerario',
      'fr': 'Générer l’itinéraire',
      'de': 'Reiseplan erstellen',
      'it': 'Genera itinerario',
      'pt': 'Gerar roteiro',
    },
    'planner.generating': {
      'en': 'Generating your itinerary...',
      'es': 'Generando tu itinerario...',
      'fr': 'Génération de votre itinéraire...',
      'de': 'Deine Reise wird erstellt...',
      'it': 'Generazione del tuo itinerario...',
      'pt': 'Gerando seu roteiro...',
    },
    'planner.selectDestination': {
      'en': 'Select a destination',
      'es': 'Selecciona un destino',
      'fr': 'Sélectionnez une destination',
      'de': 'Wähle ein Reiseziel',
      'it': 'Seleziona una destinazione',
      'pt': 'Selecione um destino',
    },
    'planner.selectDates': {
      'en': 'Select your dates',
      'es': 'Selecciona tus fechas',
      'fr': 'Sélectionnez vos dates',
      'de': 'Wähle deine Reisedaten',
      'it': 'Seleziona le date',
      'pt': 'Selecione suas datas',
    },

    // ============================================================
    // PLANNER - BUDGET VALUES
    // ============================================================

    'planner.budget.budget': {
      'en': 'Budget',
      'es': 'Económico',
      'fr': 'Économique',
      'de': 'Budget',
      'it': 'Economico',
      'pt': 'Econômico',
    },
    'planner.budget.moderate': {
      'en': 'Moderate',
      'es': 'Moderado',
      'fr': 'Modéré',
      'de': 'Mittel',
      'it': 'Moderato',
      'pt': 'Moderado',
    },
    'planner.budget.high': {
      'en': 'High',
      'es': 'Alto',
      'fr': 'Élevé',
      'de': 'Hoch',
      'it': 'Alto',
      'pt': 'Alto',
    },
    'planner.budget.luxury': {
      'en': 'Luxury',
      'es': 'Lujo',
      'fr': 'Luxe',
      'de': 'Luxus',
      'it': 'Lusso',
      'pt': 'Luxo',
    },

    // ============================================================
    // PLANNER - TRAVEL STYLES
    // ============================================================

    'planner.style.balanced': {
      'en': 'Balanced',
      'es': 'Equilibrado',
      'fr': 'Équilibré',
      'de': 'Ausgewogen',
      'it': 'Equilibrato',
      'pt': 'Equilibrado',
    },
    'planner.style.relaxed': {
      'en': 'Relaxed',
      'es': 'Relajado',
      'fr': 'Détendu',
      'de': 'Entspannt',
      'it': 'Rilassato',
      'pt': 'Relaxado',
    },
    'planner.style.adventure': {
      'en': 'Adventure',
      'es': 'Aventura',
      'fr': 'Aventure',
      'de': 'Abenteuer',
      'it': 'Avventura',
      'pt': 'Aventura',
    },
    'planner.style.luxury': {
      'en': 'Luxury',
      'es': 'Lujo',
      'fr': 'Luxe',
      'de': 'Luxus',
      'it': 'Lusso',
      'pt': 'Luxo',
    },

    // ============================================================
    // PLANNER - INTERESTS
    // ============================================================

    'planner.interest.culture': {
      'en': 'Culture',
      'es': 'Cultura',
      'fr': 'Culture',
      'de': 'Kultur',
      'it': 'Cultura',
      'pt': 'Cultura',
    },
    'planner.interest.food': {
      'en': 'Food',
      'es': 'Comida',
      'fr': 'Gastronomie',
      'de': 'Essen',
      'it': 'Cibo',
      'pt': 'Gastronomia',
    },
    'planner.interest.nature': {
      'en': 'Nature',
      'es': 'Naturaleza',
      'fr': 'Nature',
      'de': 'Natur',
      'it': 'Natura',
      'pt': 'Natureza',
    },
    'planner.interest.adventure': {
      'en': 'Adventure',
      'es': 'Aventura',
      'fr': 'Aventure',
      'de': 'Abenteuer',
      'it': 'Avventura',
      'pt': 'Aventura',
    },
    'planner.interest.shopping': {
      'en': 'Shopping',
      'es': 'Compras',
      'fr': 'Shopping',
      'de': 'Einkaufen',
      'it': 'Shopping',
      'pt': 'Compras',
    },
    'planner.interest.nightlife': {
      'en': 'Nightlife',
      'es': 'Vida nocturna',
      'fr': 'Vie nocturne',
      'de': 'Nachtleben',
      'it': 'Vita notturna',
      'pt': 'Vida noturna',
    },
    'planner.interest.relaxation': {
      'en': 'Relaxation',
      'es': 'Relajación',
      'fr': 'Détente',
      'de': 'Entspannung',
      'it': 'Relax',
      'pt': 'Relaxamento',
    },

    // ============================================================
    // TRIPS
    // ============================================================

    'trips.title': {
      'en': 'My Trips',
      'es': 'Mis Viajes',
      'fr': 'Mes Voyages',
      'de': 'Meine Reisen',
      'it': 'I Miei Viaggi',
      'pt': 'Minhas Viagens',
    },
    'trips.upcoming': {
      'en': 'Upcoming',
      'es': 'Próximos',
      'fr': 'À venir',
      'de': 'Bevorstehend',
      'it': 'In programma',
      'pt': 'Próximos',
    },
    'trips.completed': {
      'en': 'Completed',
      'es': 'Completados',
      'fr': 'Terminés',
      'de': 'Abgeschlossen',
      'it': 'Completati',
      'pt': 'Concluídos',
    },
    'trips.noTrips': {
      'en': 'No trips yet',
      'es': 'Aún no hay viajes',
      'fr': 'Aucun voyage pour le moment',
      'de': 'Noch keine Reisen',
      'it': 'Nessun viaggio ancora',
      'pt': 'Nenhuma viagem ainda',
    },
    'trips.createTrip': {
      'en': 'Create a trip',
      'es': 'Crear un viaje',
      'fr': 'Créer un voyage',
      'de': 'Reise erstellen',
      'it': 'Crea un viaggio',
      'pt': 'Criar uma viagem',
    },
    'trips.viewTrip': {
      'en': 'View trip',
      'es': 'Ver viaje',
      'fr': 'Voir le voyage',
      'de': 'Reise ansehen',
      'it': 'Visualizza viaggio',
      'pt': 'Ver viagem',
    },
    'trips.deleteTrip': {
      'en': 'Delete trip',
      'es': 'Eliminar viaje',
      'fr': 'Supprimer le voyage',
      'de': 'Reise löschen',
      'it': 'Elimina viaggio',
      'pt': 'Excluir viagem',
    },

    // ============================================================
    // TRIP DETAILS
    // ============================================================

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
      'de': 'REISE-KONSOLE',
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

    // ============================================================
    // WEATHER
    // ============================================================

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

    // ============================================================
    // ITINERARY / BUDGET
    // ============================================================

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
      'it': 'Panoramica del budget di viaggio',
      'pt': 'Resumo do orçamento',
    },
    'it.approxCost': {
      'en': 'Approximate cost for your trip. Actual prices may vary.',
      'es': 'Costo aproximado de tu viaje. Los precios reales pueden variar.',
      'fr': 'Coût approximatif de votre voyage. Les prix réels peuvent varier.',
      'de':
          'Ungefähre Kosten für deine Reise. Die tatsächlichen Preise können abweichen.',
      'it':
          'Costo approssimativo del viaggio. I prezzi reali possono variare.',
      'pt':
          'Custo aproximado da sua viagem. Os preços reais podem variar.',
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

  // ============================================================
  // RESOLUTION
  // ============================================================

  /// Resolves a translation and replaces dynamic placeholders.
  ///
  /// Example:
  ///
  ///     AppLocalizations.resolve(
  ///       'details.activitiesPlanned',
  ///       'fr',
  ///       params: {'n': '8'},
  ///     );
  ///
  /// Returns:
  ///
  ///     8 prévues
  static String resolve(
    String key,
    String language, {
    Map<String, String> params = const {},
  }) {
    final table = _strings[key];

    if (table == null) {
      return key;
    }

    var value = table[language] ?? table[fallbackLanguage] ?? key;

    for (final entry in params.entries) {
      value = value.replaceAll(
        '{${entry.key}}',
        entry.value,
      );
    }

    return value;
  }

  /// Returns the translation for [key] using the currently selected
  /// application language.
  static String current(
    String key, {
    Map<String, String> params = const {},
  }) {
    return resolve(
      key,
      AppPreferences.instance.language,
      params: params,
    );
  }
}

/// Convenient localization extension for any BuildContext.
extension AppLocalizationsX on BuildContext {
  /// Translates [key] using the current application language.
  ///
  /// Optional [params] can replace placeholders such as `{n}`.
  ///
  /// Example:
  ///
  ///     context.tr('nav.home')
  ///
  ///     context.tr(
  ///       'details.activitiesPlanned',
  ///       params: {'n': '8'},
  ///     )
  String tr(
    String key, {
    Map<String, String> params = const {},
  }) {
    return AppLocalizations.current(
      key,
      params: params,
    );
  }
}