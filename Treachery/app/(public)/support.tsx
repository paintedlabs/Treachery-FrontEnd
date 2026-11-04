import React from 'react';
import { View, Text, ScrollView, StyleSheet } from 'react-native';
import { Link } from 'expo-router';
import Head from 'expo-router/head';
import { colors, spacing, fonts, fontSize, contentMaxWidths } from '@/constants/theme';
import { OPERATOR_NAME, CONTACT_EMAIL } from '@/constants/operator';

/**
 * The support page at /support, the Support URL in App Store Connect. It tells
 * players how to contact us, report another player and delete their account
 * (App Store Guidelines 1.2 and 1.5). The (public) group is exempt from
 * AuthRedirect, so the page opens signed in or out.
 *
 * The account deletion steps repeat the privacy policy's (privacy.tsx). Change
 * both pages together.
 */
export default function SupportScreen() {
  return (
    <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent}>
      <Head>
        <title>Treachery Support</title>
      </Head>

      <View role="main" style={styles.page}>
        <View style={styles.header}>
          <Text style={styles.title} accessibilityRole="header" aria-level={1}>
            Support
          </Text>
          <Text style={styles.subtitle}>Treachery</Text>
        </View>

        <View style={styles.ornateDivider} aria-hidden>
          <View style={styles.ornateLine} />
          <Text style={styles.ornateDiamond}>&#9670;</Text>
          <View style={styles.ornateLine} />
        </View>

        <View style={styles.section}>
          <Paragraph>
            Treachery is run by {OPERATOR_NAME}. For help, to report a player or to delete your
            account, email us:
          </Paragraph>
          <EmailLink address={CONTACT_EMAIL} />
        </View>

        <Section title="Get help">
          <Paragraph>
            Email {CONTACT_EMAIL} with your device model and its iOS or Android version (or your
            browser, if you use the web app), the app version and what happened. On iPhone, the app
            version is in Profile, under About.
          </Paragraph>
        </Section>

        <Section title="Report a player or a display name">
          <Paragraph>
            Email {CONTACT_EMAIL} with the player’s display name, what happened and, if you can, the
            game code. We review every report. If a player breaks the rules, for example with an
            offensive name or by harassing other players, we may rename or remove their account.
          </Paragraph>
        </Section>

        <Section title="Delete your account">
          <Paragraph>
            <Term>On iPhone:</Term> open Profile, tap Delete Account and confirm. Deletion can’t be
            undone.
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

        <Section title="Privacy">
          <Paragraph>
            Our privacy policy explains what Treachery collects, who can see it, how long it’s kept
            and what deleting your account removes.
          </Paragraph>
          {/* No target, so expo-router opens the policy in this tab without reloading the app. */}
          <Link href="/privacy" style={styles.link}>
            Privacy Policy
          </Link>
        </Section>
      </View>
    </ScrollView>
  );
}

// Section, Paragraph, Term and EmailLink are local copies of the privacy
// policy's, so both pages look the same.

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
