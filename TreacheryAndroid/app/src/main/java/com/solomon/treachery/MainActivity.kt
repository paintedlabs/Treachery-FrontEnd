package com.solomon.treachery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.solomon.treachery.ui.navigation.TreacheryNavHost
import com.solomon.treachery.ui.theme.MtgBackground
import com.solomon.treachery.ui.theme.TreacheryTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TreacheryTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MtgBackground
                ) {
                    TreacheryNavHost()
                }
            }
        }
    }
}
