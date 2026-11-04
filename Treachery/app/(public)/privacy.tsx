import React from 'react';
import { View, Text, ScrollView, StyleSheet } from 'react-native';
import { Link } from 'expo-router';
import Head from 'expo-router/head';
import { colors, spacing, fonts, fontSize, contentMaxWidths } from '@/constants/theme';

// Placeholders the operator fills in before this page is published. Each one is
// defined only here, so a single grep finds it, and CI fails while any remain.
const OPERATOR_NAME = 'TODO_OPERATOR_NAME';
const CONTACT_EMAIL = 'TODO_CONTACT_EMAIL';
const EFFECTIVE_DATE = 'TODO_EFFECTIVE_DATE';

const GOOGLE_PRIVACY_URL = 'https://policies.google.com/privacy';
const FIREBASE_PRIVACY_URL = 'https://firebase.google.com/support/privacy';

/**
 * The privacy policy at /privacy, linked from the iOS app and App Store Connect
 * (App Store Guideline 5.1.1(i)). The (public) group is exempt from AuthRedirect,
 * so the page opens signed in or out.
 *
 * Every statement here describes what the apps, functions and firestore.rules
 * actually do. Change this page whenever they change what is collected, who can
 * see it, how long it is kept or how it is deleted.
 */
export default function PrivacyPolicyScreen() {
  return (
    <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent}>
      <Head>
        <title>Treachery Privacy Policy</title>
      </Head>

      <View role="main" style={styles.page}>
        <View style={styles.header}>
          <Text style={styles.title} accessibilityRole="header" aria-level={1}>
            Privacy Policy
          </Text>
          <Text style={styles.subtitle}>Treachery · Effective {EFFECTIVE_DATE}</Text>
        </View>

        <View style={styles.ornateDivider} aria-hidden>
          <View style={styles.ornateLine} />
          <Text style={styles.ornateDiamond}>&#9670;</Text>
          <View style={styles.ornateLine} />
        </View>

        <Paragraph>
          Treachery is a companion app for playing Magic: The Gathering with friends. It deals
          hidden roles for the Treachery format, runs Planechase and tracks life totals, on iPhone,
          Android and the web. {OPERATOR_NAME} (“we”) runs Treachery. This policy explains what the
          app collects, why, who can see it, how long it is kept and how to delete it.
        </Paragraph>

        <Section title="What we collect and why">
          <BulletList>
            <Bullet>
              <Term>Sign-in details.</Term> Your email address and password if you sign up with
              email, or your phone number if you sign in with a code sent by text message. Guests
              give neither. We use them only to sign you in, keep your account secure and send a
              password-reset email when you ask for one. Your password goes straight to Firebase
              Authentication; we never see it. To protect sign-in from abuse, Firebase
              Authentication also uses your IP address and details of your browser or app, and keeps
              a log of IP addresses for a few weeks. Phone sign-in may also use Google reCAPTCHA to
              check that you’re not a bot; reCAPTCHA sends hardware and software information about
              your device and browser to Google, which uses it to improve reCAPTCHA and for general
              security, not for personalised advertising.
            </Bullet>
            <Bullet>
              <Term>Display name.</Term> The name other players see. When you sign up, the app
              suggests one (for an email account, the part of your address before the @), and you
              can change it then or at any time in Profile. We use it to show who is who in lobbies,
              games, friend lists, friend requests and notifications.
            </Bullet>
            <Bullet>
              <Term>Account ID.</Term> A random ID that Firebase gives your account. It ties your
              games, stats and friends to you.
            </Bullet>
            <Bullet>
              <Term>Game data.</Term> The lobbies and games you create or join: your seat, role and
              identity card, life total, commander name, seat colour, planar die rolls, eliminations
              and the result. When a game ends we update your rating (ELO) and, if you entered a
              commander name, that deck’s rating, wins, losses and games played. We use this to run
              each game live on every player’s device and to show your history and stats.
            </Bullet>
            <Bullet>
              <Term>Friends.</Term> Your friends list and the friend requests you send and receive,
              so you can find each other and play again. A friend request keeps the display name its
              sender had when they sent it.
            </Bullet>
            <Bullet>
              <Term>Push token.</Term> An ID from Firebase Cloud Messaging that lets us send
              notifications to your device: when someone joins your lobby, a game starts, a player
              is eliminated or forfeits, or someone rolls chaos or planeswalks in Planechase. You
              can turn notifications off in your device or browser settings.
            </Bullet>
            <Bullet>
              <Term>Usage analytics.</Term> On iPhone and the web, Google Analytics for Firebase
              records the screens you open and what you do, such as signing in, creating or joining
              a game, sending a friend request or rolling the planar die, with details like the game
              mode and number of players, and links this to your account ID. The Android app sends
              only the events Analytics collects on its own, such as opening the app, without your
              account ID. On every platform, Analytics also collects identifiers for your app
              installation or browser, your device or browser type, operating system, app version
              and language, your approximate location (city, region and country, worked out from
              your IP address), and when and for how long you use the app. On Android it can also
              record your device’s advertising ID, which you can reset or delete in your device
              settings. On the web it uses cookies. Analytics never includes your email address,
              phone number or display name. We use it to see how Treachery is used and what to
              improve.
            </Bullet>
            <Bullet>
              <Term>Crash reports (iPhone app).</Term> If the app crashes, Firebase Crashlytics
              sends a report with where in the code it failed, your device model, iOS version, app
              version and an ID for your app installation. It may also include the usage events just
              before the crash. Reports are not labelled with your account ID. We use them to find
              and fix bugs.
            </Bullet>
            <Bullet>
              <Term>Web requests.</Term> When you open the web app, including this page, Firebase
              Hosting logs your IP address to detect abuse and to measure how the site is used.
            </Bullet>
          </BulletList>
          <Paragraph>
            Treachery doesn’t access your contacts, photos, camera, microphone or your device’s
            location, and it shows no ads. On the web, the app keeps you signed in using your
            browser’s storage.
          </Paragraph>
        </Section>

        <Section title="Who can see your information">
          <BulletList>
            <Bullet>
              Anyone who signs in to Treachery, including as a guest, can see your public profile:
              display name, rating, deck stats, friends list and the date you joined. They can find
              you by searching for your display name.
            </Bullet>
            <Bullet>
              Anyone who signs in can also look up game records, including every game a given
              account has played: who took part and who hosted (by account ID), the settings, when
              it was played and the result.
            </Bullet>
            <Bullet>
              Everyone in a game with you sees your display name, life total, commander name, seat
              colour and whether you’ve been eliminated. When the game starts, every player’s role
              and identity card are sent to every player’s device. The app doesn’t show other
              players your role until it’s revealed, but anyone in the game could read it from the
              data their device receives. Notifications to other players can include your display
              name, for example “Sam joined the game!”
            </Bullet>
            <Bullet>
              A friend request is visible only to the player who sent it and the player who received
              it.
            </Bullet>
            <Bullet>
              Your email address, phone number and push token are stored privately: other players
              can’t see them.
            </Bullet>
          </BulletList>
          <Paragraph>
            Your information travels over encrypted connections, and we don’t sell it.
          </Paragraph>
        </Section>

        <Section title="Services that process your information">
          <Paragraph>
            Treachery is built on Google Firebase. Google runs these services and processes your
            information on our behalf:
          </Paragraph>
          <BulletList>
            <Bullet>
              <Term>Firebase Authentication:</Term> sign-in, password-reset emails, text-message
              codes and reCAPTCHA checks.
            </Bullet>
            <Bullet>
              <Term>Cloud Firestore:</Term> profiles, games and friends.
            </Bullet>
            <Bullet>
              <Term>Cloud Functions for Firebase:</Term> game rules, stats, notifications and
              account deletion.
            </Bullet>
            <Bullet>
              <Term>Firebase Cloud Messaging:</Term> push notifications. On iPhone they are
              delivered through Apple’s push notification service.
            </Bullet>
            <Bullet>
              <Term>Google Analytics for Firebase:</Term> usage analytics.
            </Bullet>
            <Bullet>
              <Term>Firebase Crashlytics:</Term> crash reports from the iPhone app.
            </Bullet>
            <Bullet>
              <Term>Firebase Hosting:</Term> the web app and this page.
            </Bullet>
          </BulletList>
          <Paragraph>
            Google and Apple process your information to provide these services to us, and their
            terms with us require them to give it the same or equal protection as this policy
            describes. Google may store and process it in the United States and other countries
            where it has facilities.
          </Paragraph>
          <ExternalLink label="Google Privacy Policy" url={GOOGLE_PRIVACY_URL} />
          <ExternalLink label="How Firebase handles data" url={FIREBASE_PRIVACY_URL} />
          <Paragraph>
            Planechase card images load directly from Scryfall (scryfall.com), so Scryfall sees your
            IP address when it sends them, as any website would. We don’t share anything else with
            Scryfall.
          </Paragraph>
        </Section>

        <Section title="How long we keep it">
          <BulletList>
            <Bullet>
              Your sign-in details, profile, stats, friends, friend requests and push token: until
              you delete your account.
            </Bullet>
            <Bullet>
              Finished games stay in the history of everyone who played. If you delete your account,
              your seats in them stay, renamed “Deleted player”. Lobbies and unfinished games are
              deleted automatically after 24 hours without activity.
            </Bullet>
            <Bullet>
              Usage analytics: at most 14 months, after which only totals that don’t identify anyone
              remain. Crash reports: 90 days. Deleting your account doesn’t remove these sooner.
            </Bullet>
            <Bullet>
              Logs that include your IP address: a few weeks for sign-ins and a few months for web
              requests.
            </Bullet>
            <Bullet>
              After information is deleted, Google can take up to 180 days to clear it from its
              backups.
            </Bullet>
          </BulletList>
        </Section>

        <Section title="Deleting your account">
          <Paragraph>
            <Term>On iPhone:</Term> open Profile, tap Delete Account and confirm. This deletes your
            sign-in account, profile, stats, friends list, friend requests and push token, and takes
            you out of any lobby you’re waiting in. In past games your name becomes “Deleted player”
            and your commander name is removed; the role, life total and result stay so other
            players’ history still adds up. Those records keep your old account ID, which no longer
            links to a profile, email address or phone number. Deletion can’t be undone. If you’re
            in a game that’s still in progress, you can delete your account once that game ends; a
            game with no activity for 24 hours is removed automatically.
          </Paragraph>
          <Paragraph>
            <Term>On the web and Android:</Term> these apps can’t delete accounts yet. If you sign
            in with email or a phone number, you can sign in to the iPhone app with the same details
            and delete your account there. Otherwise, email {CONTACT_EMAIL} with your display name
            and, if you have one, the email address or phone number you sign in with. To confirm the
            account is yours, we’ll reply with a short code for you to set as your display name in
            Profile. Then we’ll delete your account in the same way as the iPhone app.
          </Paragraph>
          <Paragraph>
            Signing out doesn’t delete your account. You can’t sign back in to a guest account after
            signing out, so if you don’t want it kept, delete it before you sign out. On the web and
            Android, that means emailing us and staying signed in until we’ve confirmed it’s yours.
          </Paragraph>
        </Section>

        <Section title="Children">
          <Paragraph>
            Treachery isn’t directed to children under 13, and we don’t knowingly collect personal
            information from them. If you think a child under 13 has given us personal information,
            email {CONTACT_EMAIL} and we’ll delete it.
          </Paragraph>
        </Section>

        <Section title="Changes to this policy">
          <Paragraph>
            When we change this policy, we’ll post the new version on this page and update the
            effective date at the top. If a change affects how we use information we already have,
            we’ll also mention it in the app’s release notes.
          </Paragraph>
        </Section>

        <Section title="Contact">
          <Paragraph>
            Treachery is run by {OPERATOR_NAME}. For questions about this policy or your
            information, email us:
          </Paragraph>
          <EmailLink address={CONTACT_EMAIL} />
        </Section>
      </View>
    </ScrollView>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle} accessibilityRole="header" aria-level={2}>
        {title}
      </Text>
      {children}
    </View>
  );
}

function Paragraph({ children }: { children: React.ReactNode }) {
  return <Text style={styles.body}>{children}</Text>;
}

function Term({ children }: { children: React.ReactNode }) {
  return <Text style={styles.term}>{children}</Text>;
}

function BulletList({ children }: { children: React.ReactNode }) {
  return (
    <View role="list" style={styles.list}>
      {children}
    </View>
  );
}

function Bullet({ children }: { children: React.ReactNode }) {
  return (
    <View role="listitem" style={styles.bullet}>
      <Text style={styles.bulletMark} aria-hidden>
        &#9670;
      </Text>
      <Text style={[styles.body, styles.bulletText]}>{children}</Text>
    </View>
  );
}

// Both links render as real <a href> elements, so the browser handles clicks,
// Enter, middle-click and copying the address. expo-router routes a click itself
// only when the link has no target, so each one sets a target.

function ExternalLink({ label, url }: { label: string; url: string }) {
  return (
    <Link href={url} target="_blank" rel="noopener noreferrer" style={styles.link}>
      {label}
    </Link>
  );
}

// _self leaves mailto: to the browser, which opens the mail app and stays on
// this page. Routed through expo-router, it would open in a new, blank tab.
function EmailLink({ address }: { address: string }) {
  return (
    <Link href={`mailto:${address}`} target="_self" style={styles.link}>
      {address}
    </Link>
  );
}

const BODY_LINE_HEIGHT = 24;

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    alignItems: 'center',
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xxl,
    paddingBottom: spacing.xxl,
  },
  page: {
    width: '100%',
    maxWidth: contentMaxWidths.medium,
    gap: spacing.xl,
  },
  header: {
    alignItems: 'center',
    gap: spacing.xs,
  },
  title: {
    color: colors.primaryBright,
    fontSize: fontSize.title,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
    textAlign: 'center',
    letterSpacing: 1,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: fontSize.md,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
    textAlign: 'center',
  },
  ornateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: spacing.xxl,
  },
  ornateLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  ornateDiamond: {
    color: colors.primary,
    fontSize: 10,
  },
  section: {
    gap: spacing.md,
  },
  sectionTitle: {
    color: colors.primary,
    fontSize: fontSize.xl,
    lineHeight: 26,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  body: {
    color: colors.text,
    fontSize: fontSize.lg,
    lineHeight: BODY_LINE_HEIGHT,
  },
  term: {
    fontWeight: '700',
  },
  list: {
    gap: spacing.md,
  },
  bullet: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  bulletMark: {
    color: colors.primary,
    fontSize: 8,
    lineHeight: BODY_LINE_HEIGHT,
  },
  bulletText: {
    flex: 1,
  },
  // At least 44px tall: one 24px line plus 10px above and below.
  link: {
    alignSelf: 'flex-start',
    minHeight: 44,
    paddingVertical: 10,
    color: colors.primary,
    fontSize: fontSize.lg,
    lineHeight: BODY_LINE_HEIGHT,
    textDecorationLine: 'underline',
  },
});
