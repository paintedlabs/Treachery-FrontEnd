import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { getFunctions } from "firebase/functions";

const firebaseConfig = {
  apiKey: "AIzaSyD2DvkawVBP3kcR0rHIycEhAUFFvQFVfBs",
  authDomain: "treachery-71922.firebaseapp.com",
  projectId: "treachery-71922",
  storageBucket: "treachery-71922.firebasestorage.app",
  messagingSenderId: "573413045061",
  appId: "1:573413045061:web:09b88aeb6f67b3f590442c",
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app);
