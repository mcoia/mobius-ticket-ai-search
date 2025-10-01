import {Component} from '@angular/core';
import {SearchComponent} from './components/search/search.component';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  standalone: false,
  styleUrl: './app.component.css'
})
export class AppComponent {
  title = 'RT-Search';
  protected readonly SearchComponent = SearchComponent;
}
