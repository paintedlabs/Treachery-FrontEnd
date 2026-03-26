package com.solomon.treachery.di

import android.content.Context
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctions
import com.solomon.treachery.data.*
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class AppModule {

    @Binds
    @Singleton
    abstract fun bindAuthRepository(impl: AuthRepositoryImpl): AuthRepository

    @Binds
    @Singleton
    abstract fun bindFirestoreRepository(impl: FirestoreRepositoryImpl): FirestoreRepository

    @Binds
    @Singleton
    abstract fun bindCloudFunctionsRepository(impl: CloudFunctionsRepositoryImpl): CloudFunctionsRepository

    @Binds
    @Singleton
    abstract fun bindCardDatabase(impl: CardDatabaseImpl): CardDatabase

    @Binds
    @Singleton
    abstract fun bindPlaneDatabase(impl: PlaneDatabaseImpl): PlaneDatabase

    companion object {
        @Provides
        @Singleton
        fun provideFirebaseAuth(): FirebaseAuth = FirebaseAuth.getInstance()

        @Provides
        @Singleton
        fun provideFirestore(): FirebaseFirestore = FirebaseFirestore.getInstance()

        @Provides
        @Singleton
        fun provideFunctions(): FirebaseFunctions = FirebaseFunctions.getInstance()

        @Provides
        @Singleton
        fun provideAnalytics(@ApplicationContext context: Context): FirebaseAnalytics =
            FirebaseAnalytics.getInstance(context)
    }
}
