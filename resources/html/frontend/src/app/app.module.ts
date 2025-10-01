import {NgModule} from '@angular/core';
import {BrowserModule} from '@angular/platform-browser';

import {AppRoutingModule} from './app-routing.module';
import {AppComponent} from './app.component';
import {SearchComponent} from './components/search/search.component';
import {ResultItemComponent} from './components/result-item/result-item.component';
import {TicketDetailComponent} from './components/ticket-detail/ticket-detail.component';
import {FormsModule} from '@angular/forms';
import {HighlightPipe} from './pipes/hightlight.pipe';
import {HttpClientModule} from '@angular/common/http';

@NgModule({
  declarations: [
    AppComponent,
    SearchComponent,
    ResultItemComponent,
    TicketDetailComponent,
    HighlightPipe
  ],
  imports: [
    BrowserModule,
    AppRoutingModule,
    FormsModule,
    HttpClientModule
  ],
  providers: [],
  bootstrap: [AppComponent]
})
export class AppModule {
}
